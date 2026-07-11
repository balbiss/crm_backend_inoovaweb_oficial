class AddInstagramFieldsToInboxes < ActiveRecord::Migration[8.1]
  def change
    add_column :inboxes, :instagram_page_id, :string
    add_column :inboxes, :instagram_business_account_id, :string
    add_column :inboxes, :instagram_access_token, :string
    add_column :inboxes, :instagram_token_expires_at, :datetime
    add_column :inboxes, :instagram_username, :string
    add_index :inboxes, :instagram_page_id
  end
end
