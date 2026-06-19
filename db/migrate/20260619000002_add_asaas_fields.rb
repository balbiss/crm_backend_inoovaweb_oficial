class AddAsaasFields < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :asaas_api_key, :string
    add_column :contacts, :asaas_customer_id, :string
    add_index  :contacts, :asaas_customer_id
  end
end
