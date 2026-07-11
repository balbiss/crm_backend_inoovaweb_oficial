require 'net/http'
require 'uri'
require 'json'

module Webhooks
  class FacebookLeadsController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    GRAPH_API_VERSION = 'v21.0'.freeze

    # Handshake de verificação exigido pela Meta ao configurar o webhook.
    def verify
      if params['hub.verify_token'] == ENV['INSTAGRAM_WEBHOOK_VERIFY_TOKEN']
        render plain: params['hub.challenge']
      else
        render plain: 'invalid verify token', status: :forbidden
      end
    end

    def create
      entries = params[:entry] || []
      entries.each { |entry| handle_entry(entry) }

      render json: { status: 'ok' }
    rescue StandardError => e
      Rails.logger.error("Facebook Leads webhook error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      render json: { status: 'error', message: e.message }, status: :internal_server_error
    end

    private

    def handle_entry(entry)
      entry = entry.to_unsafe_h.with_indifferent_access if entry.respond_to?(:to_unsafe_h)
      account = Account.find_by(facebook_page_id: entry[:id])
      return unless account

      changes = entry[:changes] || []
      changes.each do |change|
        next unless change[:field] == 'leadgen'

        leadgen_id = change.dig(:value, :leadgen_id)
        next if leadgen_id.blank?
        next if Message.exists?(source_id: "leadgen_#{leadgen_id}")

        process_lead(account, leadgen_id, change[:value])
      end
    end

    def process_lead(account, leadgen_id, value)
      field_data = fetch_lead_field_data(account, leadgen_id)
      return if field_data.nil?

      lead = extract_lead(field_data, value)
      unless lead[:phone].present?
        Rails.logger.warn("Lead Ads: lead #{leadgen_id} sem telefone — ignorado")
        return
      end

      phone = normalize_phone(lead[:phone])
      contact = Contact.find_or_initialize_by(phone: phone, account_id: account.id)
      contact.name   = lead[:name].presence || contact.name || phone
      contact.email  = lead[:email].presence || contact.email
      contact.source = 'Meta Ads'
      contact.save!

      inbox = account.inboxes.where(provider: 'baileys').first
      unless inbox
        Rails.logger.warn("Lead Ads: conta #{account.id} sem inbox de WhatsApp configurada")
        return
      end

      conversation = Conversation.find_or_initialize_by(contact: contact, inbox: inbox)
      is_new = conversation.new_record?
      if is_new
        conversation.account = account
        conversation.status  = :open
        conversation.source  = 'meta_ads'
        conversation.save!
      elsif conversation.status != 'open'
        conversation.update!(status: :open)
      end

      tag = account.tags.find_or_create_by!(name: 'meta_ads') { |t| t.color = '#1877F2' }
      conversation.tags << tag unless conversation.tags.include?(tag)

      Message.create!(
        account: account, conversation: conversation, text: build_lead_note(lead),
        sender_type: 'User', sender_id: nil, source_id: "leadgen_#{leadgen_id}",
        status: :delivered, is_private: true
      )

      if is_new
        lead_text = lead[:property].present? ? "Tenho interesse no imóvel #{lead[:property]}" : "Tenho interesse em um imóvel"
        Message.create!(
          account: account, conversation: conversation, text: lead_text,
          sender_type: 'Contact', sender_id: contact.id,
          source_id: "leadgen_msg_#{leadgen_id}", status: :delivered
        )
      end

      ActionCable.server.broadcast("conversations_channel_#{account.id}", {
        event: 'conversation_updated',
        conversation: { id: conversation.id, status: 'open', source: 'meta_ads' }
      })

      dispatch_ai(account, inbox, conversation, contact, lead) if inbox.ai_enabled && is_new
    end

    def dispatch_ai(account, inbox, conversation, contact, lead)
      if rate_limited?(account)
        Rails.logger.warn("Lead Ads: limite de envios/hora atingido pra conta #{account.id}, pulando 1a mensagem automática")
        limit_tag = account.tags.find_or_create_by!(name: 'limite_atingido') { |t| t.color = '#6b7280' }
        conversation.tags << limit_tag unless conversation.tags.include?(limit_tag)
        return
      end

      phone = contact.phone
      jid = "#{phone.gsub(/\D/, '')}@s.whatsapp.net"
      contact.update_column(:jid, jid) if contact.jid.blank?

      Thread.new do
        begin
          sleep 3
          ai_service = AiAssistantService.new(inbox, conversation, extra_context: build_ai_context(lead))
          ai_response = ai_service.process_message
          if ai_response.present?
            Rails.cache.write("ai_is_replying_#{inbox.id}_#{jid}", true, expires_in: 60.seconds)
            paragraphs = ai_response.is_a?(Array) ? ai_response : ai_response.split("\n\n").reject(&:blank?)
            paragraphs.each do |para|
              baileys_id = inbox.messaging_service.send_message(jid, para.strip)
              Message.create!(
                account: account, conversation: conversation, text: para.strip,
                sender_type: 'User', sender_id: nil,
                source_id: baileys_id.presence || "ai_#{SecureRandom.hex(8)}", status: :delivered
              )
            end
          end
        rescue => e
          Rails.logger.error("Lead Ads AI error: #{e.message}")
        end
      end
    end

    def rate_limited?(account)
      key = "leadads_sends_#{account.id}_#{Time.current.strftime('%Y%m%d%H')}"
      count = Rails.cache.increment(key, 1)
      Rails.cache.write(key, count, expires_in: 1.hour) if count == 1
      max = GlobalSetting.fetch('leadads_max_per_hour').presence || 20
      count.to_i > max.to_i
    end

    def fetch_lead_field_data(account, leadgen_id)
      uri = URI.parse("https://graph.facebook.com/#{GRAPH_API_VERSION}/#{leadgen_id}")
      uri.query = URI.encode_www_form({ fields: 'field_data,ad_name,form_name', access_token: account.facebook_page_access_token })
      response = Net::HTTP.get_response(uri)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("Lead Ads: falha ao buscar dados do lead #{leadgen_id}: #{response.body}")
        return nil
      end
      JSON.parse(response.body)
    rescue => e
      Rails.logger.error("Lead Ads: erro ao buscar dados do lead #{leadgen_id}: #{e.message}")
      nil
    end

    NAME_KEYS = %w[full_name nome name].freeze
    PHONE_KEYS = %w[phone_number telefone phone celular].freeze
    EMAIL_KEYS = %w[email e-mail].freeze

    def extract_lead(field_data, value)
      fields = (field_data['field_data'] || []).each_with_object({}) do |f, h|
        h[f['name'].to_s.downcase] = (f['values'] || []).first
      end

      name = NAME_KEYS.map { |k| fields[k] }.compact.first
      phone = PHONE_KEYS.map { |k| fields[k] }.compact.first
      email = EMAIL_KEYS.map { |k| fields[k] }.compact.first

      known_keys = NAME_KEYS + PHONE_KEYS + EMAIL_KEYS
      extra_fields = fields.reject { |k, _| known_keys.include?(k) }
      property = extra_fields.values.reject(&:blank?).join(', ').presence

      {
        name: name, phone: phone, email: email, property: property,
        ad_name: field_data['ad_name'], form_name: field_data['form_name']
      }
    end

    def normalize_phone(raw)
      return nil if raw.blank?
      digits = raw.to_s.gsub(/\D/, '')
      return nil if digits.length < 8
      digits.length >= 12 ? "+#{digits}" : "+55#{digits}"
    end

    def build_ai_context(lead)
      parts = ["Este lead veio de um anúncio no Meta Ads (Instagram/Facebook)#{lead[:ad_name].present? ? ", campanha '#{lead[:ad_name]}'" : ''}."]
      parts << "Ele demonstrou interesse em: #{lead[:property]}." if lead[:property].present?
      parts << "INSTRUÇÃO: Esta é a primeira mensagem. Se apresente como assistente da imobiliária pelo nome, mencione o interesse dele e pergunte se deseja mais informações ou quer agendar uma visita."
      parts.join(' ')
    end

    def build_lead_note(lead)
      lines = ['📋 **Lead recebido via Meta Ads**']
      lines << "👤 Nome: #{lead[:name]}" if lead[:name].present?
      lines << "📱 Telefone: #{lead[:phone]}" if lead[:phone].present?
      lines << "✉️ Email: #{lead[:email]}" if lead[:email].present?
      lines << "🏠 Interesse: #{lead[:property]}" if lead[:property].present?
      lines << "📣 Anúncio: #{lead[:ad_name]}" if lead[:ad_name].present?
      lines << "📝 Formulário: #{lead[:form_name]}" if lead[:form_name].present?
      lines.join("\n")
    end
  end
end
