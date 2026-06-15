class Note < ApplicationRecord
  belongs_to :contact
  belongs_to :user
  belongs_to :account
end
