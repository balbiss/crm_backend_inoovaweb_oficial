class CreateCondominia < ActiveRecord::Migration[8.1]
  def change
    create_table :condominia do |t|
      t.string :name
      t.string :status
      t.string :building_type
      t.string :sub_type
      t.string :construction_progress
      t.string :developer
      t.string :builder
      t.string :neighborhood
      t.string :city
      t.string :state
      t.string :address
      t.date :delivery_date
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end
  end
end
