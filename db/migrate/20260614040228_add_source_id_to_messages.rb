class AddSourceIdToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :source_id, :string
  end
end
