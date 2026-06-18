class AddPortalTokenToAccounts < ActiveRecord::Migration[8.0]
  def up
    add_column :accounts, :portal_token, :string

    # Gera token para contas já existentes
    Account.find_each do |account|
      account.update_column(:portal_token, SecureRandom.hex(16))
    end

    add_index :accounts, :portal_token, unique: true
  end

  def down
    remove_index :accounts, :portal_token
    remove_column :accounts, :portal_token
  end
end
