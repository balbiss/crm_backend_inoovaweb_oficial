class Appointment < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :property
  belongs_to :user, optional: true
end
