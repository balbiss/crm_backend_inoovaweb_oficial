class AddUserIdToCoreModels < ActiveRecord::Migration[8.1]
  def change
    add_reference :contacts, :user, foreign_key: true
    add_reference :properties, :user, foreign_key: true
    add_reference :appointments, :user, foreign_key: true
  end
end
