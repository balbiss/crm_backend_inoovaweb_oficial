class Message < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  has_one_attached :attachment

  enum :status, { sent: 0, delivered: 1, read: 2, failed: 3 }
  
  # sender_type will be 'User' or 'Contact'
  # sender_id will be the id of the User or Contact

  after_create_commit :broadcast_to_conversation
  after_create_commit :update_conversation_activity

  private

  def update_conversation_activity
    conversation.update_column(:last_activity_at, Time.current)
  end

  def broadcast_to_conversation
    message_payload = {
      id: id,
      senderType: sender_type.downcase == 'user' ? 'agent' : 'contact',
      text: text,
      timestamp: created_at.iso8601,
      status: status,
      agentName: sender_type == 'User' ? User.find_by(id: sender_id)&.first_name : nil,
      isPrivate: is_private,
      attachmentUrl: attachment.attached? ? Rails.application.routes.url_helpers.rails_blob_url(attachment, host: ENV['API_HOST'] || 'http://localhost:3000') : nil,
      attachmentType: attachment.attached? ? attachment.content_type : nil
    }

    ActionCable.server.broadcast("conversations_channel", {
      event: 'message_created',
      conversation_id: conversation_id,
      message: message_payload
    })
  end
end
