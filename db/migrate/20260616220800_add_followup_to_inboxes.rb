class AddFollowupToInboxes < ActiveRecord::Migration[8.1]
  def change
    add_column :inboxes, :followup_enabled, :boolean, default: false
    add_column :inboxes, :followup_max_attempts, :integer, default: 3
    add_column :inboxes, :followup_wait_time_minutes, :integer, default: 120
  end
end
