class ConversationsController < ApplicationController
  before_action :authenticate_user!

  def index
    # Load all conversations for the user's account
    conversations = current_user.account.conversations.includes(:contact, :user, :messages)
    
    render json: conversations.map { |conv| format_conversation(conv) }
  end

  def show
    conversation = current_user.account.conversations.includes(:contact, :user, :messages).find(params[:id])
    render json: format_conversation(conversation)
  end

  def update
    conversation = current_user.account.conversations.find(params[:id])
    if conversation.update(conversation_params)
      # Broadcast status update if needed (optional for now, as frontend will update locally)
      ActionCable.server.broadcast("conversations_channel", {
        event: 'conversation_updated',
        conversation: format_conversation(conversation)
      })
      render json: format_conversation(conversation)
    else
      render json: { errors: conversation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def conversation_params
    params.require(:conversation).permit(:status)
  end

  def format_conversation(conv)
    last_message = conv.messages.order(created_at: :asc).last

    {
      id: conv.id,
      contact: {
        id: conv.contact.id,
        name: conv.contact.name,
        email: conv.contact.email,
        phone: conv.contact.phone,
        jid: conv.contact.jid,
        avatar_url: conv.contact.avatar_url,
        avatarInitials: conv.contact.name.to_s[0..1].upcase,
        avatarBg: '#0052CC', # Static for now
        status: 'online',
        cpf: conv.contact.cpf,
        birth_date: conv.contact.birth_date,
        profession: conv.contact.profession,
        gross_income: conv.contact.gross_income,
        down_payment: conv.contact.down_payment,
        fgts_balance: conv.contact.fgts_balance,
        dependents: conv.contact.dependents,
        bio: conv.contact.bio,
        company_name: conv.contact.company_name,
        country: conv.contact.country,
        city: conv.contact.city,
        cep: conv.contact.cep,
        street: conv.contact.street,
        neighborhood: conv.contact.neighborhood,
        state: conv.contact.state,
        address_number: conv.contact.address_number,
        address_complement: conv.contact.address_complement
      },
      inbox_id: conv.inbox_id,
      source: conv.source || 'whatsapp',
      preview: last_message&.text || 'Nova Conversa',
      timestamp: last_message ? last_message.created_at.strftime('%H:%M') : conv.created_at.strftime('%H:%M'),
      unread: conv.unread_count,
      messages: conv.messages.order(created_at: :asc).map do |msg|
        {
          id: msg.id,
          senderType: msg.sender_type.downcase, # 'contact' or 'user' (frontend expects 'agent')
          text: msg.text,
          timestamp: msg.created_at.iso8601,
          status: msg.status,
          agentName: msg.sender_type == 'User' ? User.find_by(id: msg.sender_id)&.first_name : nil,
          isPrivate: msg.is_private,
          attachmentUrl: msg.attachment.attached? ? Rails.application.routes.url_helpers.rails_blob_url(msg.attachment, host: ENV['API_HOST'] || 'http://localhost:3000') : nil,
          attachmentType: msg.attachment.attached? ? msg.attachment.content_type : nil
        }
      end.map { |m| m[:senderType] == 'user' ? m.merge(senderType: 'agent') : m },
      assignee: conv.user&.first_name,
      status: conv.status
    }
  end
end
