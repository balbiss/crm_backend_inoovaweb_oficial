class AddWorkingHoursToInboxes < ActiveRecord::Migration[8.1]
  def change
    add_column :inboxes, :working_hours_enabled, :boolean, default: false
    add_column :inboxes, :out_of_office_message, :text
    add_column :inboxes, :working_hours, :jsonb, default: []
  end
end
