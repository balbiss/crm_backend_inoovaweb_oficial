class AddFullDetailsToProperties < ActiveRecord::Migration[8.1]
  def change
    add_column :properties, :code, :string
    add_column :properties, :owner_name, :string
    add_column :properties, :owner_email, :string
    add_column :properties, :owner_phone, :string
    add_column :properties, :owner_phone_type, :string
    add_column :properties, :usage_type, :string
    add_column :properties, :property_type, :string
    add_column :properties, :condo_name, :string
    add_column :properties, :cep, :string
    add_column :properties, :street, :string
    add_column :properties, :number, :string
    add_column :properties, :neighborhood, :string
    add_column :properties, :city, :string
    add_column :properties, :state, :string
    add_column :properties, :country, :string
    add_column :properties, :complement, :string
    add_column :properties, :reference_point, :string
    add_column :properties, :latitude, :decimal
    add_column :properties, :longitude, :decimal
    add_column :properties, :show_address_mode, :string
    add_column :properties, :listing_type, :string
    add_column :properties, :iptu_condition, :string
    add_column :properties, :iptu_value, :decimal
    add_column :properties, :exclusivity, :boolean
    add_column :properties, :auth_start_date, :date
    add_column :properties, :auth_end_date, :date
    add_column :properties, :built_area, :integer
    add_column :properties, :total_area, :integer
    add_column :properties, :suites, :integer
    add_column :properties, :parking_spots, :integer
    add_column :properties, :agent_name, :string
    add_column :properties, :agent_phone, :string
  end
end
