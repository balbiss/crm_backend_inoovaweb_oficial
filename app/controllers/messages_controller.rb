require 'open3'
require_relative '../services/whatsapp_baileys_service'

class MessagesController < ApplicationController
  before_action :authenticate_user!

  def create
    conversation = current_user.account.conversations.find(params[:conversation_id])

    is_private_msg = params[:is_private].to_s == 'true'

    message = conversation.messages.build(
      account: current_user.account,
      sender_type: 'User',
      sender_id: current_user.id,
      text: params[:text] || '',
      is_private: is_private_msg,
      status: :sent
    )

    if params[:attachment].present?
      attach_audio_message(message, params[:attachment])
    end

    if message.save
      if !is_private_msg && %w[baileys instagram].include?(conversation.inbox&.provider)
        begin
          recipient = conversation.contact.channel_identifier
          conversation.inbox.messaging_service.send_message(recipient, message.text, message.attachment)
        rescue StandardError => e
          Rails.logger.error("Failed to send message via #{conversation.inbox.provider}: #{e.message}")
        end
      end

      # Optionally render just the new message, but we can also just return success
      render json: { success: true, message: {
        id: message.id,
        senderType: 'agent',
        text: message.text,
        timestamp: message.created_at.strftime('%H:%M'),
        status: message.status,
        agentName: current_user.first_name,
        isPrivate: message.is_private
      }}, status: :created
    else
      render json: { errors: message.errors }, status: :unprocessable_entity
    end
  end

  private

  # O gravador de áudio do navegador (MediaRecorder) produz webm/opus, mp4/aac
  # ou similar dependendo do navegador -- nenhum é o ogg/opus que o WhatsApp
  # espera pra mostrar como nota de voz (o backend já manda todo anexo de
  # áudio com "ptt: true", ver WhatsappBaileysService#send_message). Converte
  # aqui (dentro do nosso próprio container, não no baileys-api compartilhado)
  # antes de anexar, com fallback pro arquivo original se o ffmpeg falhar.
  def attach_audio_message(message, uploaded)
    if uploaded.content_type.to_s.start_with?('audio/') && !uploaded.content_type.to_s.include?('ogg')
      converted = transcode_audio_to_ogg_opus(uploaded.path)
      if converted
        message.attachment.attach(io: converted, filename: 'audio.ogg', content_type: 'audio/ogg; codecs=opus')
        return
      end
    end

    message.attachment.attach(uploaded)
  end

  def transcode_audio_to_ogg_opus(input_path)
    output = Tempfile.new(['voice', '.ogg'], binmode: true)
    _stdout, stderr, status = Open3.capture3(
      'ffmpeg', '-y', '-i', input_path, '-c:a', 'libopus', '-b:a', '32k', '-vn', output.path
    )
    unless status.success?
      Rails.logger.error("ffmpeg falhou ao converter áudio pra ogg/opus: #{stderr}")
      return nil
    end

    StringIO.new(File.binread(output.path))
  rescue => e
    Rails.logger.error("Falha ao converter áudio pra ogg/opus: #{e.message}")
    nil
  ensure
    output&.close!
  end
end
