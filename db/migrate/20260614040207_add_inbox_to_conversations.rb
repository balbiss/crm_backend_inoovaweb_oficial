class AddInboxToConversations < ActiveRecord::Migration[8.1]
  def change
    add_reference :conversations, :inbox, null: true, foreign_key: true
  end
end
