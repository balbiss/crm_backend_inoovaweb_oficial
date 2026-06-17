class AddRoundRobinToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :available_for_roundrobin, :boolean, default: false, null: false
    add_column :users, :queue_position, :integer
    add_index :users, [:account_id, :available_for_roundrobin, :queue_position],
              name: 'index_users_on_account_roundrobin_queue'
  end
end
