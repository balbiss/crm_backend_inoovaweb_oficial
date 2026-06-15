class CreateAppointments < ActiveRecord::Migration[8.1]
  def change
    create_table :appointments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :property, null: false, foreign_key: true
      t.string :broker_name
      t.string :status
      t.date :appointment_date
      t.string :start_time
      t.string :end_time

      t.timestamps
    end
  end
end
