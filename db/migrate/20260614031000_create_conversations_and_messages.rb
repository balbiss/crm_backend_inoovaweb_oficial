class CreateConversationsAndMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :conversations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :user, foreign_key: true # assignee
      t.integer :status, default: 0
      t.string :source
      t.integer :unread_count, default: 0

      t.timestamps
    end

    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string :sender_type, null: false
      t.integer :sender_id
      t.text :text
      t.boolean :is_private, default: false
      t.integer :status, default: 0

      t.timestamps
    end
  end
end
