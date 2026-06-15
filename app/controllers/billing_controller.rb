class BillingController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_empresa!

  def checkout
    account = current_user.account

    # Se já tem um customer_id, vamos usar. Se não, a sessão vai criar um.
    session_params = {
      payment_method_types: ['card'],
      line_items: [{
        price: ENV['STRIPE_PRICE_ID'] || 'price_dummy', # O ideal é pegar do painel do Stripe
        quantity: 1,
      }],
      mode: 'subscription',
      success_url: "#{ENV['FRONTEND_URL'] || 'http://localhost:5173'}/settings/account?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{ENV['FRONTEND_URL'] || 'http://localhost:5173'}/settings/account",
      client_reference_id: account.id.to_s
    }

    if account.stripe_customer_id.present?
      session_params[:customer] = account.stripe_customer_id
    else
      session_params[:customer_email] = current_user.email
    end

    begin
      session = Stripe::Checkout::Session.create(session_params)
      render json: { url: session.url }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def portal
    account = current_user.account

    if account.stripe_customer_id.blank?
      return render json: { error: 'Customer not found' }, status: :not_found
    end

    begin
      session = Stripe::BillingPortal::Session.create({
        customer: account.stripe_customer_id,
        return_url: "#{ENV['FRONTEND_URL'] || 'http://localhost:5173'}/settings/account",
      })

      render json: { url: session.url }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def authorize_empresa!
    unless current_user.admin? || current_user.empresa?
      render json: { error: 'Unauthorized' }, status: :forbidden
    end
  end
end
