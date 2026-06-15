class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name
      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.string :subscription_status

      t.timestamps
    end
  end
end
