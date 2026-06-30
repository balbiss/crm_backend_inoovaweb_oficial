class Contact < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true
  has_many :conversations, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :appointments, dependent: :destroy

  BROADCAST_FIELDS = %w[name first_name last_name phone temperature status source intention user_id avatar_url].freeze

  after_save :broadcast_contact_update, if: -> { saved_changes.keys.any? { |k| BROADCAST_FIELDS.include?(k) } }

  private

  def broadcast_contact_update
    ActionCable.server.broadcast("conversations_channel_#{account_id}", {
      event: 'contact_updated',
      contact_id: id
    })
  end
end
