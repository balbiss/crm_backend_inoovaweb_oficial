class AccountsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_subscription_access!, only: [:show, :update_password]

  def show
    account  = current_user.account
    api_host = ENV['API_HOST'] || 'http://localhost:3000'
    render json: {
      account_name:        account.name,
      email:               current_user.email,
      subscription_status: account.subscription_status || 'pending',
      trial_ends_at:       account.trial_ends_at,
      plan_name:           'Plano Premium',
      portal_token:        account.portal_token,
      asaas_configured:    account.asaas_api_key.present?,
      asaas_api_key:       mask_key(account.asaas_api_key),
      asaas_sandbox:       account.asaas_sandbox?,
      facebook_page_name:  account.facebook_page_name,
      webhook_urls: {
        canal_pro: "#{api_host}/webhooks/canal_pro/#{account.portal_token}",
        zap:       "#{api_host}/webhooks/zap/#{account.portal_token}",
        viva_real: "#{api_host}/webhooks/viva_real/#{account.portal_token}"
      }
    }
  end

  def test_asaas
    account = current_user.account
    return render json: { ok: false, message: 'API Key não configurada.' } if account.asaas_api_key.blank?

    result = AsaasService.new(account.asaas_api_key, sandbox: account.asaas_sandbox?).test_connection
    if result[:ok]
      render json: { ok: true, message: "Conectado: #{result[:name]}" }
    else
      render json: { ok: false, message: result[:error] || 'Falha na conexão.' }
    end
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
    params.require(:account).permit(:name, :asaas_api_key, :asaas_sandbox)
  end

  def mask_key(key)
    return nil if key.blank?
    "#{key[0..7]}#{'*' * (key.length - 12)}#{key[-4..]}"
  end

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end
end
