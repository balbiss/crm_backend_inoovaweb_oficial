class InboxMember < ApplicationRecord
  belongs_to :inbox
  belongs_to :user
  
  validates :user_id, uniqueness: { scope: :inbox_id, message: "already belongs to this inbox" }
end
