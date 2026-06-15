class Appointment < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :property
end
