require 'net/http'
require 'uri'

module Webhooks
  class InstagramController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

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
      Rails.logger.error("Instagram webhook error: #{e.message}")
      render json: { status: 'error', message: e.message }, status: :internal_server_error
    end

    private

    def handle_entry(entry)
      entry = entry.to_unsafe_h.with_indifferent_access if entry.respond_to?(:to_unsafe_h)
      page_id = entry[:id]
      inbox = Inbox.find_by(instagram_page_id: page_id, provider: 'instagram')
      return unless inbox

      messaging_events = entry[:messaging] || []
      messaging_events.each { |event| handle_messaging_event(inbox, event) }
    end

    def handle_messaging_event(inbox, event)
      event = event.with_indifferent_access
      message = event[:message]
      return unless message.present?

      mid = message[:mid]
      is_echo = message[:is_echo]
      igsid = is_echo ? event.dig(:recipient, :id) : event.dig(:sender, :id)
      return unless igsid

      if is_echo
        handle_echo(inbox, igsid, mid)
        return
      end

      next_message(inbox, igsid, mid, message)
    end

    # Eco de mensagem enviada por nós mesmos: se já está no banco, foi o CRM que
    # mandou (equivalente ao "echo da IA" do Baileys) — ignora sem pausar nada.
    # Se NÃO está no banco, foi um humano respondendo direto pelo app do Instagram
    # (equivalente ao "fromMe real" do Baileys) — pausa a IA.
    def handle_echo(inbox, igsid, mid)
      return if mid.present? && Message.exists?(source_id: mid)
      return unless inbox.ai_enabled

      Rails.logger.info("IA pausada para #{igsid} devido a intervenção humana (echo real do Instagram).")
      Rails.cache.write("ai_paused_#{inbox.id}_#{igsid}", Time.current.to_i)

      Thread.new do
        begin
          conv = inbox.conversations.joins(:contact).where(contacts: { instagram_id: igsid }).first
          if conv
            tag = conv.account.tags.find_or_create_by!(name: 'agente_off') { |t| t.color = '#f97316' }
            conv.tags << tag unless conv.tags.include?(tag)
            ActionCable.server.broadcast("conversations_channel_#{conv.account_id}", {
              event: 'conversation_tags_updated',
              conversation_id: conv.id,
              tags: conv.tags.map { |t| { id: t.id, name: t.name, color: t.color } }
            })
          end
        rescue => e
          Rails.logger.error("Erro ao aplicar tag agente_off (Instagram): #{e.message}")
        end
      end
    end

    def next_message(inbox, igsid, mid, message)
      return if mid.present? && Message.exists?(source_id: mid)

      account = inbox.account
      text = message[:text].to_s

      contact = Contact.find_or_create_by(instagram_id: igsid, account_id: account.id) do |c|
        c.name = igsid
        c.source = 'Instagram'
      end
      return if contact.status == 'blocked'

      fetch_profile_info(inbox, contact) if contact.avatar_url.blank? || contact.name == igsid

      conversation = Conversation.find_or_create_by(contact: contact, inbox: inbox) do |conv|
        conv.status = :open
        conv.account = account
        conv.source = 'instagram'
      end

      message_record = Message.create!(
        account: conversation.account,
        conversation: conversation,
        text: text,
        sender_type: 'Contact',
        sender_id: contact.id,
        source_id: mid,
        status: :delivered
      )

      attach_media(message_record, message[:attachments]) if message[:attachments].present?
      message_record.update(text: '📎 Anexo recebido') if message_record.text.blank? && message_record.attachment.attached?

      dispatch_ai(inbox, conversation, igsid)
    end

    def fetch_profile_info(inbox, contact)
      Thread.new do
        begin
          url = inbox.messaging_service.fetch_profile_picture_url(contact.instagram_id)
          contact.update(avatar_url: url) if url.present?
        rescue => e
          Rails.logger.error("Failed to fetch Instagram profile info for #{contact.instagram_id}: #{e.message}")
        end
      end
    end

    def attach_media(message_record, attachments)
      attachment = attachments.first
      url = attachment&.dig(:payload, :url)
      return if url.blank?

      uri = URI.parse(url)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 20) { |http| http.get(uri) }
      return unless response.is_a?(Net::HTTPSuccess)

      type = attachment[:type] || 'file'
      content_type = { 'image' => 'image/jpeg', 'video' => 'video/mp4', 'audio' => 'audio/mpeg' }[type] || 'application/octet-stream'
      extension = { 'image' => 'jpg', 'video' => 'mp4', 'audio' => 'mp3' }[type] || 'bin'

      message_record.attachment.attach(
        io: StringIO.new(response.body),
        filename: "#{message_record.source_id}.#{extension}",
        content_type: content_type
      )
    rescue => e
      Rails.logger.error("Failed to download Instagram attachment: #{e.message}")
    end

    def dispatch_ai(inbox, conversation, igsid)
      return unless inbox.ai_enabled

      is_paused = Rails.cache.read("ai_paused_#{inbox.id}_#{igsid}")
      if is_paused
        Rails.logger.info("IA pulou atendimento (Instagram) para #{igsid} porque está em cooldown (Humano assumiu).")
        return
      end

      if conversation.status == 'resolved'
        conversation.update!(status: :open)
        tags_a_remover = conversation.tags.select { |t| %w[agente_off com_atendente].include?(t.name) }
        tags_a_remover.each { |t| conversation.conversation_tags.where(tag_id: t.id).delete_all }
        conversation.tags.reset
        ActionCable.server.broadcast("conversations_channel_#{conversation.account_id}", {
          event:        'conversation_updated',
          conversation: { id: conversation.id, status: 'open', snoozed_until: nil }
        })
      elsif conversation.status == 'snoozed'
        conversation.update!(status: :open, snoozed_until: nil)
        ActionCable.server.broadcast("conversations_channel_#{conversation.account_id}", {
          event:        'conversation_updated',
          conversation: { id: conversation.id, status: 'open', snoozed_until: nil }
        })
      end

      debounce_key = "debounce_ai_#{inbox.id}_#{igsid}"
      current_time = Time.now.to_f
      Rails.cache.write(debounce_key, current_time)

      Thread.new do
        begin
          sleep 8

          if Rails.cache.read(debounce_key) == current_time
            Rails.logger.info("Iniciando AiAssistantService (Instagram) para a conversa #{conversation.id}")

            ai_service = AiAssistantService.new(inbox, conversation)
            ai_response_text = ai_service.process_message

            if ai_response_text.present?
              Rails.cache.write("ai_is_replying_#{inbox.id}_#{igsid}", true, expires_in: 60.seconds)
              messaging_service = inbox.messaging_service

              paragraphs = ai_response_text.is_a?(Array) ? ai_response_text : ai_response_text.split("\n\n").reject(&:blank?)

              paragraphs.each do |paragraph|
                messaging_service.send_presence_update(igsid, 'composing')

                typing_time = [(paragraph.length / 15.0).round, 3].max
                typing_time = [typing_time, 15].min
                sleep typing_time

                Rails.cache.write("ai_is_replying_#{inbox.id}_#{igsid}", true, expires_in: 30.seconds)
                messaging_service.send_presence_update(igsid, 'paused')

                message_id = messaging_service.send_message(igsid, paragraph.strip)

                Message.create!(
                  account: conversation.account,
                  conversation: conversation,
                  text: paragraph.strip,
                  sender_type: 'User',
                  sender_id: nil,
                  source_id: message_id.presence || "ai_#{SecureRandom.hex(8)}",
                  status: :delivered
                )
              end
            end
          else
            Rails.logger.info("Debounce cancelou a execução da IA (Instagram, nova mensagem recebida) para #{igsid}")
          end
        rescue => e
          Rails.logger.error("Erro fatal no AiAssistantService (Instagram): #{e.message}")
        end
      end
    end
  end
end
