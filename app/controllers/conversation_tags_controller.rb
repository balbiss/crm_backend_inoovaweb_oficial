class ConversationTagsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation

  def index
    render json: @conversation.tags.map { |t| { id: t.id, name: t.name, color: t.color } }
  end

  def create
    name = params[:name].to_s.strip.downcase.gsub(/\s+/, '_')
    color = params[:color].presence || '#6b7280'
    return render json: { error: 'Nome obrigatório' }, status: :unprocessable_entity if name.blank?

    tag = current_user.account.tags.find_or_create_by!(name: name) do |t|
      t.color = color
    end

    unless @conversation.tags.include?(tag)
      @conversation.tags << tag
      broadcast_update
    end

    render json: { id: tag.id, name: tag.name, color: tag.color }
  end

  def destroy
    tag = @conversation.tags.find_by(id: params[:id])
    if tag
      # Remover a etiqueta 'agente_off' manualmente equivale a clicar "Retomar IA":
      # também limpa a pausa e tira 'com_atendente' junto, já que a IA está retomando.
      # O corretor já atribuído (conversation.user_id) não é alterado aqui.
      if tag.name == 'agente_off'
        contact_jid = @conversation.contact.channel_identifier
        Rails.cache.delete("ai_paused_#{@conversation.inbox_id}_#{contact_jid}")
        com_atendente = @conversation.tags.find { |t| t.name == 'com_atendente' }
        @conversation.tags.delete(com_atendente) if com_atendente
      end

      @conversation.tags.delete(tag)
      broadcast_update
    end
    head :no_content
  end

  private

  def set_conversation
    @conversation = current_user.account.conversations.find(params[:conversation_id])
  end

  def broadcast_update
    ActionCable.server.broadcast("conversations_channel_#{@conversation.account_id}", {
      event: 'conversation_tags_updated',
      conversation_id: @conversation.id,
      tags: @conversation.tags.map { |t| { id: t.id, name: t.name, color: t.color } }
    })
  end
end
