class Inbox < ApplicationRecord
  has_many :conversations
  has_many :inbox_members, dependent: :destroy
  has_many :users, through: :inbox_members, dependent: :destroy
end
