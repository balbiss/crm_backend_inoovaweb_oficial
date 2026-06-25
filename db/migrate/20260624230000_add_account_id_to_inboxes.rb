class AddAccountIdToInboxes < ActiveRecord::Migration[8.1]
  def up
    add_column :inboxes, :account_id, :bigint
    add_index :inboxes, :account_id

    # Backfill via conversas existentes
    execute <<~SQL
      UPDATE inboxes
      SET account_id = (
        SELECT account_id FROM conversations
        WHERE conversations.inbox_id = inboxes.id
        LIMIT 1
      )
      WHERE account_id IS NULL
    SQL

    # Fallback: via inbox_members → users
    execute <<~SQL
      UPDATE inboxes
      SET account_id = (
        SELECT users.account_id
        FROM inbox_members
        JOIN users ON users.id = inbox_members.user_id
        WHERE inbox_members.inbox_id = inboxes.id
        LIMIT 1
      )
      WHERE account_id IS NULL
    SQL

    orphan_count = execute("SELECT COUNT(*) FROM inboxes WHERE account_id IS NULL").first["count"].to_i
    Rails.logger.warn("AddAccountIdToInboxes: #{orphan_count} inbox(es) sem account após backfill") if orphan_count > 0

    add_foreign_key :inboxes, :accounts
  end

  def down
    remove_foreign_key :inboxes, :accounts
    remove_index :inboxes, :account_id
    remove_column :inboxes, :account_id
  end
end
