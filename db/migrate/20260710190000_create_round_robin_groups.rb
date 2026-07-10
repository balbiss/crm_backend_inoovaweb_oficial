class CreateRoundRobinGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :round_robin_groups do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end
  end
end
