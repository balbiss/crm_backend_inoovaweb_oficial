class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def index
    # Retorna notificações não lidas e as 5 últimas lidas
    unread = current_user.account.notifications.where(read_at: nil).order(created_at: :desc)
    read = current_user.account.notifications.where.not(read_at: nil).order(created_at: :desc).limit(5)
    
    render json: {
      unread: unread,
      read: read,
      unread_count: unread.count
    }
  end

  def mark_all_read
    current_user.account.notifications.where(read_at: nil).update_all(read_at: Time.current)
    render json: { message: 'Todas marcadas como lidas' }
  end

  def mark_as_read
    notification = current_user.account.notifications.find(params[:id])
    notification.update(read_at: Time.current)
    render json: { message: 'Marcada como lida' }
  end
end
