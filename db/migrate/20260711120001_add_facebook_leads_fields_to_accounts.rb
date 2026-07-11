class AddFacebookLeadsFieldsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :facebook_page_id, :string
    add_column :accounts, :facebook_page_access_token, :string
    add_column :accounts, :facebook_page_name, :string
    add_column :accounts, :facebook_token_expires_at, :datetime
    add_index :accounts, :facebook_page_id
  end
end
