class CreateSupportTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :support_tickets do |t|
      t.references :account, null: false, foreign_key: true
      t.string :title
      t.integer :status

      t.timestamps
    end
  end
end
