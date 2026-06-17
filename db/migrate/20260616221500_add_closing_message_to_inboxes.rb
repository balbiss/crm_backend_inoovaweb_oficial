class AddClosingMessageToInboxes < ActiveRecord::Migration[8.1]
  def change
    add_column :inboxes, :followup_send_closing_message, :boolean, default: false
    add_column :inboxes, :followup_closing_message, :text
  end
end
