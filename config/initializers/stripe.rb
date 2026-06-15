Rails.configuration.stripe = {
  publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'] || 'pk_test_dummy',
  secret_key:      ENV['STRIPE_SECRET_KEY'] || 'sk_test_dummy'
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]
