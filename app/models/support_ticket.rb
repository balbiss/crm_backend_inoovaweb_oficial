class SupportTicket < ApplicationRecord
  belongs_to :account
  has_many :support_ticket_messages, dependent: :destroy
end
