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
      message.attachment.attach(params[:attachment])
    end

    if message.save
      if !is_private_msg && conversation.inbox&.provider == 'baileys'
        begin
          recipient = conversation.contact.jid.presence || conversation.contact.phone
          WhatsappBaileysService.new(conversation.inbox).send_message(recipient, message.text, message.attachment)
        rescue StandardError => e
          Rails.logger.error("Failed to send message via Baileys: #{e.message}")
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
end
