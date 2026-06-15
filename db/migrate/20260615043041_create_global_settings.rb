class CreateGlobalSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :global_settings do |t|
      t.string :key
      t.text :value

      t.timestamps
    end
    add_index :global_settings, :key, unique: true
  end
end
