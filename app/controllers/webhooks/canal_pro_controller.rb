module Webhooks
  class CanalProController < ApplicationController
    skip_before_action :verify_authenticity_token,  raise: false
    skip_before_action :authenticate_user!,          raise: false
    skip_before_action :check_subscription_access!, raise: false

    PORTAL_TAG_COLORS = {
      'canal_pro' => '#7c3aed',
      'zap'       => '#FF5A00',
      'viva_real' => '#0062CC'
    }.freeze

    def create
      account = Account.find_by(portal_token: params[:token])
      unless account
        render json: { error: 'token inválido' }, status: :not_found and return
      end

      source_portal = params[:source_portal].presence || 'canal_pro'
      lead = extract_lead(params, source_portal)

      unless lead[:phone].present? || lead[:email].present?
        Rails.logger.warn("Portal #{source_portal}: lead sem telefone nem email — ignorado")
        render json: { status: 'ignored', reason: 'no_contact_info' } and return
      end

      phone = normalize_phone(lead[:phone])

      contact = if phone.present?
        Contact.find_or_initialize_by(phone: phone, account_id: account.id)
      else
        Contact.find_or_initialize_by(email: lead[:email], account_id: account.id)
      end

      contact.name   = lead[:name].presence || contact.name || phone || lead[:email]
      contact.email  = lead[:email].presence || contact.email
      contact.phone  = phone.presence || contact.phone
      contact.source = source_portal
      contact.save!

      # Inboxes da conta: busca via conversas (mais confiável, owner nem sempre está em inbox_members)
      via_conversations = account.conversations.pluck(:inbox_id).uniq.compact
      via_members       = InboxMember.joins(:user)
                                     .where(users: { account_id: account.id })
                                     .pluck(:inbox_id).uniq
      account_inbox_ids = (via_conversations + via_members).uniq

      setting_key = "#{source_portal}_inbox_id"
      forced_id   = GlobalSetting.fetch(setting_key).presence || GlobalSetting.fetch('canal_pro_inbox_id').presence
      inbox = if forced_id
        Inbox.find_by(id: forced_id)
      elsif account_inbox_ids.any?
        # Conta pode ter mais de um número/inbox (ex: número antigo desativado
        # e um novo em uso) -- sem checar conexão de verdade, sempre ganhava o
        # de menor ID, que pode ser um inbox morto com prompt/persona antigos
        # (achado testando de verdade: lead caindo num WhatsApp desconectado,
        # com a IA respondendo com nome de uma marca antiga que nem existe
        # mais pro cliente).
        candidates = Inbox.where(id: account_inbox_ids, ai_enabled: true, provider: 'baileys')
        connected_inbox = candidates.detect { |c| WhatsappBaileysService.new(c).connected? rescue false }
        # Nenhum candidato conectado agora (ex: número atual caiu
        # momentaneamente) -- em vez de cair pro de menor id (que pode ser
        # um número morto há meses, nunca mais vai reconectar), prefere o
        # que esteve conectado mais recentemente de verdade.
        most_recently_connected = candidates.max_by { |c| Rails.cache.read("inbox:#{c.id}:last_connected_at").to_i }
        connected_inbox || most_recently_connected || candidates.first || Inbox.where(id: account_inbox_ids).first
      else
        Inbox.where(ai_enabled: true).first || Inbox.first
      end

      unless inbox
        Rails.logger.warn("Portal #{source_portal}: conta #{account.id} sem inbox configurada")
        render json: { status: 'contact_created', conversation: false } and return
      end

      conversation = Conversation.find_or_initialize_by(contact: contact, inbox: inbox)
      is_new = conversation.new_record?

      if conversation.new_record?
        conversation.account = account
        conversation.status  = :open
        conversation.source  = source_portal
        conversation.save!
      elsif conversation.status != 'open'
        conversation.update!(status: :open)
      end

      # Tag com cor da plataforma (canal_pro=roxo, zap=laranja, viva_real=azul)
      tag_color = PORTAL_TAG_COLORS[source_portal] || '#7c3aed'
      tag = account.tags.find_or_create_by!(name: source_portal) { |t| t.color = tag_color }
      conversation.tags << tag unless conversation.tags.include?(tag)

      # Nota privada com dados do lead
      Message.create!(
        account:      account,
        conversation: conversation,
        text:         build_lead_note(lead),
        sender_type:  'User',
        sender_id:    nil,
        source_id:    "#{source_portal}_#{SecureRandom.hex(8)}",
        status:       :delivered,
        is_private:   true
      )

      # Mensagem do lead (texto que ele enviou no portal) — dá contexto à IA
      if is_new
        lead_text = lead[:message].presence ||
                    (lead[:property].present? ? "Tenho interesse no imóvel #{lead[:property]}" : "Tenho interesse em um imóvel")
        Message.create!(
          account:      account,
          conversation: conversation,
          text:         lead_text,
          sender_type:  'Contact',
          sender_id:    contact.id,
          source_id:    "portal_msg_#{SecureRandom.hex(8)}",
          status:       :delivered
        )
      end

      ActionCable.server.broadcast("conversations_channel_#{account.id}", {
        event:        'conversation_updated',
        conversation: { id: conversation.id, status: 'open', source: source_portal }
      })

      # IA via WhatsApp se tiver telefone, AI ativa e conversa nova
      if inbox.ai_enabled && phone.present? && is_new
        jid = "#{phone.gsub(/\D/, '')}@s.whatsapp.net"
        contact.update_column(:jid, jid) if contact.jid.blank?

        Thread.new do
          begin
            sleep 3
            ai_service = AiAssistantService.new(inbox, conversation, extra_context: build_portal_context(lead, source_portal))
            ai_response = ai_service.process_message
            if ai_response.present?
              Rails.cache.write("ai_is_replying_#{inbox.id}_#{jid}", true, expires_in: 60.seconds)
              paragraphs = ai_response.is_a?(Array) ? ai_response : ai_response.split("\n\n").reject(&:blank?)
              paragraphs.each do |para|
                baileys_id = WhatsappBaileysService.new(inbox).send_message(jid, para.strip)
                Message.create!(
                  account:      account,
                  conversation: conversation,
                  text:         para.strip,
                  sender_type:  'User',
                  sender_id:    nil,
                  source_id:    baileys_id.presence || "ai_#{SecureRandom.hex(8)}",
                  status:       :delivered
                )
              end
            end
          rescue => e
            Rails.logger.error("Portal #{source_portal} AI error: #{e.message}")
          end
        end
      end

      render json: { status: 'ok', conversation_id: conversation.id, contact_id: contact.id }
    rescue => e
      Rails.logger.error("Portal webhook error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      render json: { status: 'error', message: e.message }, status: :internal_server_error
    end

    private

    def extract_lead(p, source_portal = 'canal_pro')
      p = p.to_unsafe_h.with_indifferent_access rescue p

      # Formato aninhado Canal Pro: { lead: { nome:, telefone:, fones: [...] }, anuncio: { ... } }
      if p[:lead].is_a?(Hash)
        l = p[:lead].with_indifferent_access
        fones = l[:fones].is_a?(Array) ? l[:fones].first&.dig(:numero) : nil
        {
          name:        l[:nome]     || l[:name],
          email:       l[:email],
          phone:       l[:telefone] || l[:celular] || l[:fone] || fones,
          message:     strip_portal_boilerplate(l[:mensagem] || l[:texto] || l[:msg]),
          property:    p.dig(:anuncio, :titulo) || p.dig(:anuncio, :ref) || p.dig(:produto, :titulo),
          source:      p[:portal]   || p[:origem]  || source_portal.humanize,
          temperature: nil
        }
      else
        # Formato flat Grupo ZAP (ZAP Imóveis / Viva Real / OLX Imóveis):
        # Prioriza phoneNumber (DDD+fone combinados) sobre phone/ddd separados
        raw_phone = p[:phoneNumber].presence ||
                    combine_ddd_phone(p[:ddd], p[:phone]) ||
                    p[:phone] || p[:telefone] || p[:celular] || p[:fone]

        property = p[:produto]  || p[:imovel]   || p[:titulo]          ||
                   p[:ref]      || p[:clientListingId] || p[:originListingId]

        {
          name:        p[:nome]      || p[:name],
          email:       p[:email],
          phone:       raw_phone,
          message:     strip_portal_boilerplate(p[:mensagem] || p[:texto] || p[:msg] || p[:message]),
          property:    property,
          source:      p[:leadOrigin] || p[:portal] || p[:origem] || source_portal.humanize,
          temperature: p[:temperature]
        }
      end
    end

    # O Grupo ZAP (OLX/ZAP Imóveis/Viva Real) cola um rodapé na mensagem do
    # lead repetindo nome/e-mail/telefone (já capturados nos campos próprios)
    # e um link de pesquisa de satisfação -- sem isso, a mensagem que aparece
    # como se fosse do lead na tela fica poluída com lixo do portal.
    def strip_portal_boilerplate(text)
      return text if text.blank?
      text.split(/A seguir,?\s*dados para contato/i).first.to_s.strip.presence || text
    end

    def combine_ddd_phone(ddd, phone)
      return nil if ddd.blank? || phone.blank?
      "#{ddd}#{phone}"
    end

    def normalize_phone(raw)
      return nil if raw.blank?
      digits = raw.to_s.gsub(/\D/, '')
      return nil if digits.length < 8
      # >= 12 dígitos: já tem código de país (ex: 5511975020518)
      # 10-11 dígitos: número brasileiro sem +55 → adiciona
      digits.length >= 12 ? "+#{digits}" : "+55#{digits}"
    end

    def build_portal_context(lead, source_portal)
      portal_names = { 'canal_pro' => 'Canal Pro', 'zap' => 'ZAP Imóveis', 'viva_real' => 'Viva Real' }
      parts = ["Este lead chegou via #{portal_names[source_portal] || source_portal} (portal imobiliário)."]
      parts << "Ele tem interesse no imóvel de referência: #{lead[:property]}." if lead[:property].present?
      parts << "Temperatura indicada pelo portal: #{lead[:temperature]}." if lead[:temperature].present?
      parts << "INSTRUÇÃO: Esta é a primeira mensagem. Se apresente como assistente da imobiliária pelo nome, mencione o imóvel que ele perguntou e pergunte se deseja mais informações ou quer agendar uma visita."
      parts.join(" ")
    end

    def build_lead_note(lead)
      lines = ["📋 **Lead recebido via #{lead[:source]}**"]
      lines << "👤 Nome: #{lead[:name]}"               if lead[:name].present?
      lines << "📱 Telefone: #{lead[:phone]}"           if lead[:phone].present?
      lines << "✉️ Email: #{lead[:email]}"              if lead[:email].present?
      lines << "🏠 Imóvel: #{lead[:property]}"          if lead[:property].present?
      lines << "🌡️ Temperatura: #{lead[:temperature]}"  if lead[:temperature].present?
      lines << "💬 Mensagem: #{lead[:message]}"         if lead[:message].present?
      lines.join("\n")
    end
  end
end
