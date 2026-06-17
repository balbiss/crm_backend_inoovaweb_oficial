class AddBotPromptToInboxes < ActiveRecord::Migration[8.1]
  def change
    add_column :inboxes, :bot_prompt, :text
  end
end
