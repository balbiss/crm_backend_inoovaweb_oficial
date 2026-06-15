class Inbox < ApplicationRecord
  has_many :conversations, dependent: :destroy
end
