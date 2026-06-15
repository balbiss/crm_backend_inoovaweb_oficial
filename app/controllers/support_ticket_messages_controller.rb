class SupportTicketMessagesController < ApplicationController
  before_action :authenticate_user!

  def create
    ticket = current_user.account.support_tickets.find(params[:support_ticket_id])
    
    # Se o chamado estava resolvido e o cliente mandou mensagem, reabre.
    ticket.update(status: 0) if ticket.status == 2

    message = ticket.support_ticket_messages.build(message_params)
    message.user = current_user

    if message.save
      render json: message, status: :created
    else
      render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def message_params
    params.require(:support_ticket_message).permit(:body)
  end
end
