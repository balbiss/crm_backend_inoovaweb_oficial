class CreateProperties < ActiveRecord::Migration[8.1]
  def change
    create_table :properties do |t|
      t.string :title
      t.text :description
      t.decimal :price
      t.integer :bedrooms
      t.integer :bathrooms
      t.string :status
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end
  end
end
