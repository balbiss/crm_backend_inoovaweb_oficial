module Webhooks
  class StripeController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false
    # Se estivesse usando JWT globalmente no controller base, precisamos pular
    # skip_before_action :authenticate_user! # caso tenha no ApplicationController
    
    def create
      payload = request.body.read
      sig_header = request.env['HTTP_STRIPE_SIGNATURE']
      endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET'] || 'whsec_dummy'
      event = nil

      begin
        event = Stripe::Webhook.construct_event(
          payload, sig_header, endpoint_secret
        )
      rescue JSON::ParserError => e
        # Invalid payload
        render json: { error: 'Invalid payload' }, status: 400
        return
      rescue Stripe::SignatureVerificationError => e
        # Invalid signature
        # Para ambiente local de testes sem webhook secret configurado, podemos passar direto:
        if Rails.env.development? && endpoint_secret == 'whsec_dummy'
          event = Stripe::Event.construct_from(JSON.parse(payload, symbolize_names: true))
        else
          render json: { error: 'Invalid signature' }, status: 400
          return
        end
      end

      # Handle the event
      case event.type
      when 'checkout.session.completed'
        session = event.data.object
        account_id = session.client_reference_id

        if account_id.present?
          account = Account.find_by(id: account_id)
          if account
            account.update(
              stripe_customer_id: session.customer,
              stripe_subscription_id: session.subscription,
              subscription_status: 'active'
            )
          end
        end

      when 'customer.subscription.updated'
        subscription = event.data.object
        account = Account.find_by(stripe_subscription_id: subscription.id)
        if account
          account.update(subscription_status: subscription.status)
        end

      when 'customer.subscription.deleted'
        subscription = event.data.object
        account = Account.find_by(stripe_subscription_id: subscription.id)
        if account
          account.update(subscription_status: 'canceled')
        end
      else
        puts "Unhandled event type: #{event.type}"
      end

      render json: { message: 'success' }, status: 200
    end
  end
end
