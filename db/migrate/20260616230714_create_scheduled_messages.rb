class CreateScheduledMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.text :text
      t.datetime :send_at
      t.string :status, default: 'pending'

      t.timestamps
    end
  end
end
