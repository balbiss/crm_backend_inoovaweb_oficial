class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :contacts, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :properties, dependent: :destroy
  has_many :condominiums, dependent: :destroy
  has_many :support_tickets, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :tags, dependent: :destroy

  before_create :set_trial_period

  def active_subscription?
    return false if ['blocked', 'canceled', 'unpaid'].include?(subscription_status)
    subscription_status == 'active' || (trial_ends_at.present? && trial_ends_at > Time.current)
  end

  private

  def set_trial_period
    self.trial_ends_at ||= 7.days.from_now
  end
end
