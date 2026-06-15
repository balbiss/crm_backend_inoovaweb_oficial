class AddRealEstateFieldsToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :cpf, :string
    add_column :contacts, :birth_date, :date
    add_column :contacts, :profession, :string
    add_column :contacts, :gross_income, :decimal
    add_column :contacts, :down_payment, :decimal
    add_column :contacts, :fgts_balance, :decimal
    add_column :contacts, :dependents, :integer
  end
end
