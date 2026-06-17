class AddAiSettingsToInboxes < ActiveRecord::Migration[8.1]
  def change
    add_column :inboxes, :ai_enabled, :boolean, default: false
    add_column :inboxes, :ai_name, :string
    add_column :inboxes, :ai_prompt, :text
    add_column :inboxes, :ai_temperature, :float, default: 0.7
  end
end
