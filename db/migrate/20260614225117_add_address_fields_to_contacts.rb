class AddAddressFieldsToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :cep, :string
    add_column :contacts, :street, :string
    add_column :contacts, :neighborhood, :string
    add_column :contacts, :state, :string
    add_column :contacts, :address_number, :string
    add_column :contacts, :address_complement, :string
  end
end
