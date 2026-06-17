class AddPerformanceIndexesToTables < ActiveRecord::Migration[8.1]
  def change
    add_index :messages, :source_id unless index_exists?(:messages, :source_id)
    add_index :messages, [:sender_type, :sender_id] unless index_exists?(:messages, [:sender_type, :sender_id])
    add_index :contacts, :phone unless index_exists?(:contacts, :phone)
    add_index :inboxes, :phone_number unless index_exists?(:inboxes, :phone_number)
    add_index :conversations, :status unless index_exists?(:conversations, :status)
  end
end
