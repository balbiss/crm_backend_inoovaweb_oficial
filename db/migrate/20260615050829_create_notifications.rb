class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :account, null: false, foreign_key: true
      t.string :title
      t.string :message
      t.string :link
      t.datetime :read_at

      t.timestamps
    end
  end
end
