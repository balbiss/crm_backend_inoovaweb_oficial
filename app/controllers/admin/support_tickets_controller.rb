class Admin::SupportTicketsController < Admin::BaseController
  def index
    # Retorna todos os tickets de todas as contas
    tickets = SupportTicket.includes(:account, :support_ticket_messages).order(updated_at: :desc).map do |t|
      {
        id: t.id,
        title: t.title,
        status: t.status,
        created_at: t.created_at,
        updated_at: t.updated_at,
        account_name: t.account.name,
        messages_count: t.support_ticket_messages.size
      }
    end
    render json: tickets
  end

  def show
    ticket = SupportTicket.find(params[:id])
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
    render json: { 
      ticket: {
        id: ticket.id,
        title: ticket.title,
        status: ticket.status,
        account_name: ticket.account.name
      }, 
      messages: messages 
    }
  end

  def reply
    ticket = SupportTicket.find(params[:id])
    message = ticket.support_ticket_messages.build(body: params[:message])
    message.user = current_user
    
    # Ao responder, se estiver fechado, reabre, ou marca como "Respondido" (poderia ser status 1 = Em Andamento)
    ticket.status = 1 if ticket.status == 0 || ticket.status == 2
    
    ActiveRecord::Base.transaction do
      message.save!
      ticket.save!

      # Cria notificação para a empresa
      ticket.account.notifications.create!(
        title: "Novo retorno no chamado ##{ticket.id}",
        message: "O suporte respondeu ao seu chamado: #{ticket.title}",
        link: "/suporte"
      )
    end

    render json: message, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def close
    ticket = SupportTicket.find(params[:id])
    ticket.update!(status: 2) # Resolvido
    render json: { message: 'Ticket encerrado com sucesso.' }
  end
end
