class ScheduledMessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation

  def index
    scheduled_messages = @conversation.scheduled_messages.where(status: 'pending').order(send_at: :asc)
    render json: scheduled_messages.map { |msg| format_scheduled_message(msg) }
  end

  def create
    @scheduled_message = @conversation.scheduled_messages.new(
      text: params[:text],
      send_at: params[:send_at]
    )

    if params[:attachment].present?
      @scheduled_message.attachment.attach(params[:attachment])
    end

    if @scheduled_message.save
      # Agenda o envio via SolidQueue para o horário exato
      SendScheduledMessageJob.set(wait_until: @scheduled_message.send_at).perform_later(@scheduled_message.id)

      render json: format_scheduled_message(@scheduled_message), status: :created
    else
      render json: { errors: @scheduled_message.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @scheduled_message = @conversation.scheduled_messages.find(params[:id])
    
    # Marcamos como cancelada em vez de deletar para manter histórico ou evitar job quebrar feio
    if @scheduled_message.update(status: 'cancelled')
      head :no_content
    else
      render json: { error: 'Não foi possível cancelar o agendamento' }, status: :unprocessable_entity
    end
  end

  private

  def set_conversation
    @conversation = current_user.account.conversations.find(params[:conversation_id])
  end

  def format_scheduled_message(msg)
    {
      id: msg.id,
      text: msg.text,
      send_at: msg.send_at.iso8601,
      status: msg.status,
      attachmentUrl: msg.attachment.attached? ? Rails.application.routes.url_helpers.rails_blob_url(msg.attachment, host: ENV['API_HOST'] || 'http://localhost:3000') : nil,
      attachmentType: msg.attachment.attached? ? msg.attachment.content_type : nil,
      attachmentName: msg.attachment.attached? ? msg.attachment.filename.to_s : nil
    }
  end
end
