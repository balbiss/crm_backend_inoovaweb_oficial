class SupportTicketsController < ApplicationController
  before_action :authenticate_user!
  
  def index
    # Retorna os tickets da empresa atual
    tickets = current_user.account.support_tickets.order(created_at: :desc)
    render json: tickets
  end

  def show
    ticket = current_user.account.support_tickets.find(params[:id])
    messages = ticket.support_ticket_messages.includes(:user).order(created_at: :asc).map do |msg|
      {
        id: msg.id,
        body: msg.body,
        created_at: msg.created_at,
        user: {
          id: msg.user.id,
          name: "#{msg.user.first_name} #{msg.user.last_name}".strip,
          role: msg.user.role
        }
      }
    end
    render json: { ticket: ticket, messages: messages }
  end

  def create
    ticket = current_user.account.support_tickets.build(ticket_params)
    ticket.status = 0 # Aberto

    if ticket.save
      if params[:message].present?
        ticket.support_ticket_messages.create!(user: current_user, body: params[:message])
      end
      render json: ticket, status: :created
    else
      render json: { errors: ticket.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def ticket_params
    params.require(:support_ticket).permit(:title)
  end
end
