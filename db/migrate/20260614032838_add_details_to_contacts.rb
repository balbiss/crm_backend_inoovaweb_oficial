class AddDetailsToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :first_name, :string
    add_column :contacts, :last_name, :string
    add_column :contacts, :city, :string
    add_column :contacts, :country, :string
    add_column :contacts, :bio, :text
    add_column :contacts, :company_name, :string
  end
end
