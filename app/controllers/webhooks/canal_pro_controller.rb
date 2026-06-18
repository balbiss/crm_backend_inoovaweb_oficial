module Webhooks
  class CanalProController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false
    skip_before_action :authenticate_user!
    skip_before_action :check_subscription_access!

    def create
      account = Account.find_by(portal_token: params[:token])
      unless account
        render json: { error: 'token inválido' }, status: :not_found and return
      end

      lead = extract_lead(params)

      unless lead[:phone].present? || lead[:email].present?
        Rails.logger.warn("Canal Pro: lead sem telefone nem email — ignorado")
        render json: { status: 'ignored', reason: 'no_contact_info' } and return
      end

      # Normaliza telefone
      phone = normalize_phone(lead[:phone])

      # Encontra ou cria contato
      contact = if phone.present?
        Contact.find_or_initialize_by(phone: phone, account_id: account.id)
      else
        Contact.find_or_initialize_by(email: lead[:email], account_id: account.id)
      end

      contact.name   = lead[:name].presence || contact.name || phone || lead[:email]
      contact.email  = lead[:email].presence || contact.email
      contact.phone  = phone.presence || contact.phone
      contact.source = 'canal_pro'
      contact.save!

      # Inbox: usa a configurada em GlobalSetting ou a primeira com AI ativa
      inbox_id = GlobalSetting.fetch('canal_pro_inbox_id').presence
      inbox = inbox_id ? account.inboxes.find_by(id: inbox_id) : account.inboxes.where(ai_enabled: true).first
      inbox ||= account.inboxes.first

      unless inbox
        Rails.logger.warn("Canal Pro: conta #{account.id} sem inbox configurada")
        render json: { status: 'contact_created', conversation: false } and return
      end

      # Cria conversa (uma por contato/inbox)
      conversation = Conversation.find_or_initialize_by(contact: contact, inbox: inbox)
      is_new = conversation.new_record?

      if conversation.new_record?
        conversation.account = account
        conversation.status  = :open
        conversation.source  = 'canal_pro'
        conversation.save!
      elsif conversation.status != 'open'
        conversation.update!(status: :open)
      end

      # Adiciona tag canal_pro
      tag = account.tags.find_or_create_by!(name: 'canal_pro') { |t| t.color = '#7c3aed' }
      conversation.tags << tag unless conversation.tags.include?(tag)

      # Mensagem interna com os dados do lead (nota privada)
      lead_info = build_lead_note(lead)
      Message.create!(
        account:      account,
        conversation: conversation,
        text:         lead_info,
        sender_type:  'User',
        sender_id:    nil,
        source_id:    "canal_pro_#{SecureRandom.hex(8)}",
        status:       :delivered,
        is_private:   true
      )

      # Broadcast para atualizar o painel em tempo real
      ActionCable.server.broadcast('conversations_channel', {
        event:           'conversation_updated',
        conversation:    { id: conversation.id, status: 'open', source: 'canal_pro' }
      })

      # Dispara IA via WhatsApp se tiver telefone e AI ativa
      if inbox.ai_enabled && phone.present? && is_new
        jid = "#{phone.gsub(/\D/, '')}@s.whatsapp.net"
        contact.update_column(:jid, jid) if contact.jid.blank?

        Thread.new do
          begin
            sleep 3
            ai_service = AiAssistantService.new(inbox, conversation)
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
            Rails.logger.error("Canal Pro AI error: #{e.message}")
          end
        end
      end

      render json: { status: 'ok', conversation_id: conversation.id, contact_id: contact.id }
    rescue => e
      Rails.logger.error("Canal Pro webhook error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      render json: { status: 'error', message: e.message }, status: :internal_server_error
    end

    private

    # Parser flexível — suporta diferentes formatos do Canal Pro
    def extract_lead(p)
      p = p.to_unsafe_h.with_indifferent_access rescue p

      # Formato aninhado: { lead: { nome:, telefone:, ... }, anuncio: { ... } }
      if p[:lead].is_a?(Hash)
        l = p[:lead].with_indifferent_access
        fones = l[:fones].is_a?(Array) ? l[:fones].first&.dig(:numero) : nil
        {
          name:     l[:nome] || l[:name],
          email:    l[:email],
          phone:    l[:telefone] || l[:celular] || l[:fone] || fones,
          message:  l[:mensagem] || l[:texto] || l[:msg],
          property: p.dig(:anuncio, :titulo) || p.dig(:anuncio, :ref) || p.dig(:produto, :titulo),
          source:   p[:portal] || p[:origem] || 'Canal Pro'
        }
      else
        # Formato flat: { nome:, email:, telefone:, ... }
        {
          name:     p[:nome]     || p[:name],
          email:    p[:email],
          phone:    p[:telefone] || p[:celular] || p[:fone] || p[:phone],
          message:  p[:mensagem] || p[:texto]   || p[:msg]  || p[:message],
          property: p[:produto]  || p[:imovel]  || p[:titulo] || p[:ref],
          source:   p[:portal]   || p[:origem]  || 'Canal Pro'
        }
      end
    end

    def normalize_phone(raw)
      return nil if raw.blank?
      digits = raw.to_s.gsub(/\D/, '')
      return nil if digits.length < 8
      digits.length >= 12 ? "+#{digits}" : "+55#{digits}"
    end

    def build_lead_note(lead)
      lines = ["📋 **Lead recebido via #{lead[:source] || 'Canal Pro'}**"]
      lines << "👤 Nome: #{lead[:name]}"          if lead[:name].present?
      lines << "📱 Telefone: #{lead[:phone]}"      if lead[:phone].present?
      lines << "✉️ Email: #{lead[:email]}"         if lead[:email].present?
      lines << "🏠 Imóvel: #{lead[:property]}"     if lead[:property].present?
      lines << "💬 Mensagem: #{lead[:message]}"    if lead[:message].present?
      lines.join("\n")
    end
  end
end
