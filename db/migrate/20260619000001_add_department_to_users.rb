class AddDepartmentToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :department, :string, default: 'corretor', null: false
    add_index  :users, :department
  end
end
