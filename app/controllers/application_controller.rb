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
end
