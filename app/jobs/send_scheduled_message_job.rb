class SendScheduledMessageJob < ApplicationJob
  queue_as :default

  def perform(scheduled_message_id)
    scheduled_message = ScheduledMessage.find_by(id: scheduled_message_id)
    return unless scheduled_message
    return if scheduled_message.status != 'pending'

    conversation = scheduled_message.conversation
    inbox = conversation.inbox
    baileys_service = WhatsappBaileysService.new(inbox)
    remote_jid = conversation.contact.jid || conversation.contact.phone

    begin
      attachment_to_send = scheduled_message.attachment.attached? ? scheduled_message.attachment : nil
      
      # Enviar via Baileys API
      success = baileys_service.send_message(remote_jid, scheduled_message.text, attachment_to_send)

      if success
        # Criar a mensagem local no banco
        message = Message.create!(
          account: conversation.account,
          conversation: conversation,
          text: scheduled_message.text,
          sender_type: 'User',
          sender_id: conversation.user_id,
          source_id: "scheduled_#{SecureRandom.hex(8)}",
          status: :delivered
        )

        if attachment_to_send
          # Copiar o anexo da ScheduledMessage para a Message final
          message.attachment.attach(attachment_to_send.blob)
        end

        scheduled_message.update!(status: 'sent')

        # Atualizar last_activity
        conversation.update_column(:last_activity_at, Time.current)

        # Transmitir via ActionCable para a UI em tempo real
        ActionCable.server.broadcast("conversation_#{conversation.id}_messages", {
          message: message.as_json.merge(
            attachmentUrl: message.attachment.attached? ? Rails.application.routes.url_helpers.rails_blob_url(message.attachment, host: ENV['API_HOST'] || 'http://localhost:3000') : nil,
            attachmentType: message.attachment.attached? ? message.attachment.content_type : nil
          ),
          type: 'new_message'
        })
      else
        scheduled_message.update!(status: 'failed')
      end

    rescue StandardError => e
      Rails.logger.error("Error sending scheduled message #{scheduled_message_id}: #{e.message}")
      scheduled_message.update!(status: 'failed')
    end
  end
end
