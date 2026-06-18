class ApplicationController < ActionController::API
  before_action :check_subscription_access!

  private

  def check_subscription_access!
    return unless current_user && current_user.account
    return if devise_controller? || self.class == BillingController || self.class == Webhooks::StripeController

    unless current_user.account.active_subscription?
      render json: { error: 'subscription_required', message: 'Seu período de teste expirou ou sua assinatura está inativa.' }, status: :payment_required
    end
  end

  # Garante que apenas donos (empresa/admin) acessem o endpoint.
  # Chame via before_action :require_owner! nos controllers filhos.
  def require_owner!
    unless owner?
      render json: { error: 'forbidden', message: 'Acesso restrito ao administrador da imobiliária.' }, status: :forbidden
    end
  end

  def owner?
    current_user&.empresa? || current_user&.admin?
  end
end
