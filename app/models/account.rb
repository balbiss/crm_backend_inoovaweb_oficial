class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :contacts, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :properties, dependent: :destroy
  has_many :condominiums, dependent: :destroy
  has_many :support_tickets, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :inboxes, dependent: :destroy
  has_many :appointments, dependent: :destroy
  has_many :round_robin_groups, dependent: :destroy

  before_create :set_trial_period
  before_create :generate_portal_token

  def active_subscription?
    return false if ['blocked', 'canceled', 'unpaid'].include?(subscription_status)
    subscription_status == 'active' || (trial_ends_at.present? && trial_ends_at > Time.current)
  end

  private

  def set_trial_period
    self.trial_ends_at ||= 7.days.from_now
  end

  def generate_portal_token
    self.portal_token ||= SecureRandom.hex(16)
  end
end
