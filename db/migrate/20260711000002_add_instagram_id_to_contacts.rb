class AddInstagramIdToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :instagram_id, :string
    add_index :contacts, :instagram_id
    add_index :contacts, [:account_id, :instagram_id], name: "index_contacts_on_account_id_and_instagram_id"
  end
end
