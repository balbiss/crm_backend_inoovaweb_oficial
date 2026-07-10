class AddRoundRobinGroupToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :round_robin_group, null: true, foreign_key: true
  end
end
