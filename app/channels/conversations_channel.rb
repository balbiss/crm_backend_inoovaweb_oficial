class ConversationsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "conversations_channel_#{current_user.account_id}"
  end

  def unsubscribed
  end
end
