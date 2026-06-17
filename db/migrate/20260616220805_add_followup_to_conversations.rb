class AddFollowupToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :followup_count, :integer, default: 0
    add_column :conversations, :last_activity_at, :datetime
  end
end
