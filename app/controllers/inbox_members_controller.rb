class InboxMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_inbox

  def index
    # Retorna todos os usuários da conta, com uma flag indicando se pertencem à caixa
    @users = current_user.account.users
    @members = @inbox.users

    render json: @users.map { |user|
      user.as_json(only: [:id, :name, :email]).merge(is_member: @members.include?(user))
    }
  end

  def create
    @user = current_user.account.users.find(params[:user_id])
    unless @inbox.users.include?(@user)
      @inbox.users << @user
    end
    render json: { success: true }
  end

  def destroy
    @user = current_user.account.users.find(params[:id])
    @inbox.users.delete(@user)
    render json: { success: true }
  end

  private

  def set_inbox
    @inbox = current_user.account.inboxes.find(params[:inbox_id])
  end
end
