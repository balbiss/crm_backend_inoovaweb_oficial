class AccountsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_subscription_access!, only: [:show, :update_password]

  def show
    account = current_user.account
    render json: {
      account_name: account.name,
      email: current_user.email,
      subscription_status: account.subscription_status || 'pending',
      trial_ends_at: account.trial_ends_at,
      plan_name: 'Plano Premium' # No futuro pode vir do Stripe
    }
  end

  def update
    account = current_user.account
    if account.update(account_params)
      render json: { message: 'Configurações atualizadas com sucesso!' }, status: :ok
    else
      render json: { error: account.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def update_password
    if current_user.update_with_password(password_params)
      # Ao trocar a senha, o Devise desloga o usuário, então precisamos re-logar:
      bypass_sign_in(current_user)
      render json: { message: 'Senha alterada com sucesso!' }, status: :ok
    else
      render json: { error: current_user.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(:name)
  end

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end
end
