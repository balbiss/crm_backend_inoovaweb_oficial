class AddCondominiumToAppointments < ActiveRecord::Migration[8.1]
  def change
    add_reference :appointments, :condominium, foreign_key: true, null: true
    change_column_null :appointments, :property_id, true
  end
end
