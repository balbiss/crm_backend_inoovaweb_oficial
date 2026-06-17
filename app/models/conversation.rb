class Conversation < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :user, optional: true
  belongs_to :inbox, optional: true

  has_many :messages, dependent: :destroy
  has_many :scheduled_messages, dependent: :destroy
  has_many :conversation_tags, dependent: :destroy
  has_many :tags, through: :conversation_tags

  enum :status, { open: 0, pending: 1, resolved: 2, snoozed: 3 }
end
