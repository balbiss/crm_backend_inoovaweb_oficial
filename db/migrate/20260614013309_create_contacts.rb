class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.string :name
      t.string :email
      t.string :phone
      t.string :status
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end
  end
end
