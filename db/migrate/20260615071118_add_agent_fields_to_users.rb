class AddAgentFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :phone, :string
    add_column :users, :status, :string, default: 'active'
    add_column :users, :permissions, :jsonb, default: {}
  end
end
