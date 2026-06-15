class CreateInboxes < ActiveRecord::Migration[8.1]
  def change
    create_table :inboxes do |t|
      t.string :name
      t.string :provider
      t.string :api_url
      t.string :api_key
      t.string :phone_number

      t.timestamps
    end
  end
end
