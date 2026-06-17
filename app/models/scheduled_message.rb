class ScheduledMessage < ApplicationRecord
  belongs_to :conversation
  has_one_attached :attachment
end
