class AddCustomAttributesToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :custom_attributes, :jsonb, default: {}
  end
end
