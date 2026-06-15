class AddTrialEndsAtToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :trial_ends_at, :datetime
  end
end
