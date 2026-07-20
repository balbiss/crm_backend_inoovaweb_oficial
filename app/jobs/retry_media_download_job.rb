class RetryMediaDownloadJob < ApplicationJob
  queue_as :default

  # As 3 tentativas imediatas do webhook (0s/2s/4s) cobrem a maioria dos
  # "stream errored out" do Baileys, que normalmente se resolvem sozinhos em
  # poucos segundos. Quando a instabilidade dura mais que isso (minutos, não
  # segundos), essas tentativas continuam em background bem mais espaçadas.
  DELAYS = [30.seconds, 2.minutes, 5.minutes, 10.minutes].freeze

  def perform(message_id, source_id, inbox_id, filename, mimetype, attempt = 1)
    message_record = Message.find_by(id: message_id)
    return if message_record.nil? || message_record.attachment.attached?

    inbox = Inbox.find_by(id: inbox_id)
    return if inbox.nil?

    decoded_media = WhatsappBaileysService.new(inbox).fetch_media(source_id)

    if decoded_media.present?
      message_record.attachment.attach(
        io: StringIO.new(decoded_media),
        filename: filename,
        content_type: mimetype
      )
      message_record.update(text: '📎 Anexo recebido') if message_record.text == '📎 Arquivo não pôde ser baixado'

      if mimetype.start_with?('audio/') && inbox.ai_enabled
        begin
          transcription = AiAssistantService.transcribe_audio(decoded_media, filename, inbox)
          message_record.update(text: "[Áudio Transcrito] #{transcription}") if transcription.present?
        rescue => e
          Rails.logger.error("Erro no Whisper (retry): #{e.message}")
        end
      end
    elsif attempt < DELAYS.size
      RetryMediaDownloadJob.set(wait: DELAYS[attempt]).perform_later(message_id, source_id, inbox_id, filename, mimetype, attempt + 1)
    end
  end
end
