class AddRealEstateKpisToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :temperature, :string
    add_column :contacts, :source, :string
    add_column :contacts, :intention, :string
  end
end
