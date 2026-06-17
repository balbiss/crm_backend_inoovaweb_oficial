class ConversationsController < ApplicationController
  before_action :authenticate_user!

  def index
    conversations = current_user.account.conversations
      .includes(:user, :tags, messages: { attachment_attachment: :blob }, contact: { notes: :user })
    users_hash = User.where(account_id: current_user.account_id).index_by(&:id)
    render json: conversations.map { |conv| format_conversation(conv, users_hash) }
  end

  def show
    conversation = current_user.account.conversations
      .includes(:user, :tags, messages: { attachment_attachment: :blob }, contact: { notes: :user })
      .find(params[:id])
    users_hash = User.where(account_id: current_user.account_id).index_by(&:id)
    render json: format_conversation(conversation, users_hash)
  end

  def update
    conversation = current_user.account.conversations.includes(:tags).find(params[:id])
    users_hash = User.where(account_id: current_user.account_id).index_by(&:id)
    old_user_id = conversation.user_id

    if conversation.update(conversation_params)
      new_user_id = conversation.user_id
      if new_user_id != old_user_id
        tag = current_user.account.tags.find_or_create_by!(name: 'com_atendente') { |t| t.color = '#8b5cf6' }
        if new_user_id.present?
          unless conversation.tags.any? { |t| t.id == tag.id }
            conversation.tags << tag
            conversation.tags.reset
          end
        else
          conversation.conversation_tags.where(tag_id: tag.id).delete_all
          conversation.tags.reset
        end
        ActionCable.server.broadcast('conversations_channel', {
          event: 'conversation_tags_updated',
          conversation_id: conversation.id,
          tags: conversation.tags.map { |t| { id: t.id, name: t.name, color: t.color } }
        })
      end

      ActionCable.server.broadcast("conversations_channel", {
        event: 'conversation_updated',
        conversation: format_conversation(conversation, users_hash)
      })
      render json: format_conversation(conversation, users_hash)
    else
      render json: { errors: conversation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def ai_status
    conversation = current_user.account.conversations.includes(:contact).find(params[:id])
    contact_jid = conversation.contact.jid.presence || conversation.contact.phone
    cache_key = "ai_paused_#{conversation.inbox_id}_#{contact_jid}"
    paused_at = Rails.cache.read(cache_key)

    if paused_at
      remaining = [(30 * 60) - (Time.current.to_i - paused_at.to_i), 0].max
      render json: { paused: true, remaining_seconds: remaining }
    else
      render json: { paused: false, remaining_seconds: 0 }
    end
  end

  def resume_ai
    conversation = current_user.account.conversations.includes(:contact, :tags).find(params[:id])
    contact_jid = conversation.contact.jid.presence || conversation.contact.phone
    Rails.cache.delete("ai_paused_#{conversation.inbox_id}_#{contact_jid}")
    agente_off = conversation.tags.find { |t| t.name == 'agente_off' }
    if agente_off
      conversation.conversation_tags.where(tag_id: agente_off.id).delete_all
      remaining_tags = conversation.tags.reject { |t| t.id == agente_off.id }
      ActionCable.server.broadcast('conversations_channel', {
        event: 'conversation_tags_updated',
        conversation_id: conversation.id,
        tags: remaining_tags.map { |t| { id: t.id, name: t.name, color: t.color } }
      })
    end
    render json: { success: true }
  end

  def generate_summary
    conversation = current_user.account.conversations.includes(:messages).find(params[:id])
    
    recent_messages = conversation.messages.order(created_at: :asc).last(30)
    
    chat_history = recent_messages.map do |msg|
      "#{msg.sender_type == 'Contact' ? 'Cliente' : 'Corretor/IA'}: #{msg.text || '[Mídia]'}"
    end.join("\n")

    system_prompt = <<~PROMPT
      Você é um assistente de imobiliária. Seu objetivo é ler o histórico da conversa abaixo e gerar um resumo curto, direto e objetivo do atendimento.
      Destaque as principais informações como:
      - O que o cliente busca (imóvel/perfil)
      - Faixa de valor
      - Região de interesse
      - Próximos passos combinados
      Não crie informações que não estejam no texto. Retorne apenas o resumo.
    PROMPT

    begin
      api_key = GlobalSetting.find_by(key: 'openai_api_key')&.value.presence || ENV['OPENAI_API_KEY']
      client = OpenAI::Client.new(access_token: api_key)
      
      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: "Histórico:\n#{chat_history}" }
          ],
          temperature: 0.3
        }
      )
      
      summary = response.dig("choices", 0, "message", "content")
      render json: { summary: summary }
    rescue StandardError => e
      Rails.logger.error("Error generating summary: \#{e.message}")
      render json: { error: "Erro ao gerar resumo." }, status: :unprocessable_entity
    end
  end

  private

  def conversation_params
    params.require(:conversation).permit(:status, :user_id)
  end

  def format_conversation(conv, users_hash = {})
    # Sort in memory — avoids N+1 from .order() on eager-loaded association
    sorted_messages = conv.messages.sort_by(&:created_at)
    last_message = sorted_messages.last
    sorted_notes = conv.contact.notes.sort_by { |n| -n.created_at.to_i }

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
        avatarBg: '#0052CC',
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
        address_complement: conv.contact.address_complement,
        notes: sorted_notes.map do |n|
          {
            id: n.id,
            content: n.content,
            created_at: n.created_at,
            author: n.user&.first_name || 'Sistema'
          }
        end
      },
      inbox_id: conv.inbox_id,
      source: conv.source || 'whatsapp',
      preview: last_message&.text || 'Nova Conversa',
      timestamp: last_message ? last_message.created_at.strftime('%H:%M') : conv.created_at.strftime('%H:%M'),
      unread: conv.unread_count,
      messages: sorted_messages.map do |msg|
        sender_type = msg.sender_type.downcase
        {
          id: msg.id,
          senderType: sender_type == 'user' ? 'agent' : sender_type,
          text: msg.text,
          timestamp: msg.created_at.iso8601,
          status: msg.status,
          agentName: msg.sender_type == 'User' ? (users_hash[msg.sender_id]&.first_name || 'Agente') : nil,
          isPrivate: msg.is_private,
          attachmentUrl: msg.attachment.attached? ? Rails.application.routes.url_helpers.rails_blob_url(msg.attachment, host: ENV['API_HOST'] || 'http://localhost:3000') : nil,
          attachmentType: msg.attachment.attached? ? msg.attachment.content_type : nil
        }
      end,
      assignee: conv.user&.first_name,
      assignee_id: conv.user_id,
      status: conv.status,
      tags: conv.tags.map { |t| { id: t.id, name: t.name, color: t.color } }
    }
  end
end
