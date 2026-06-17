class CreateInboxMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :inbox_members do |t|
      t.references :inbox, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    
    add_index :inbox_members, [:inbox_id, :user_id], unique: true
  end
end
