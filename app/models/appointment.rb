class Appointment < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :property, optional: true
  belongs_to :condominium, optional: true
  belongs_to :user, optional: true
end
