class RoundRobinGroup < ApplicationRecord
  belongs_to :account
  has_many :users, dependent: :nullify
  has_many :inboxes, dependent: :nullify

  validates :name, presence: true
end
