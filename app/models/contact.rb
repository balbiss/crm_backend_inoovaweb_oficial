class Contact < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true
  has_many :conversations, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :appointments, dependent: :destroy

  after_save :broadcast_contact_update

  private

  def broadcast_contact_update
    ActionCable.server.broadcast("conversations_channel", {
      event: 'contact_updated',
      contact_id: id
    })
  end
end
