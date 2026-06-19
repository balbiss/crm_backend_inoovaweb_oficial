class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def vapid_public_key
    render json: { vapid_public_key: ENV.fetch('VAPID_PUBLIC_KEY', '') }
  end

  def create
    sub = current_user.push_subscriptions.find_or_initialize_by(endpoint: params[:endpoint])
    sub.assign_attributes(p256dh_key: params[:p256dh], auth_key: params[:auth])
    sub.save!
    head :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def unsubscribe
    current_user.push_subscriptions.find_by(endpoint: params[:endpoint])&.destroy
    head :ok
  end
end
