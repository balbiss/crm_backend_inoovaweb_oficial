class Contact < ApplicationRecord
  belongs_to :account
  has_many :conversations, dependent: :destroy
  has_many :notes, dependent: :destroy
end
