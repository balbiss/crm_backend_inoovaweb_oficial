class AddSnoozedUntilToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :snoozed_until, :datetime
  end
end
