class AddDetailsToCondominiums < ActiveRecord::Migration[7.1]
  def change
    add_column :condominia, :land_area, :string
    add_column :condominia, :built_area, :string
    add_column :condominia, :on_site_sales, :boolean
    add_column :condominia, :construction_year, :string
    add_column :condominia, :administrator, :string
    add_column :condominia, :architecture, :string
    add_column :condominia, :min_price, :decimal
    add_column :condominia, :max_price, :decimal
    add_column :condominia, :tags, :string
    add_column :condominia, :condominium_types, :string
    add_column :condominia, :cep, :string
    add_column :condominia, :street, :string
    add_column :condominia, :number, :string
    add_column :condominia, :country, :string
    add_column :condominia, :reference_point, :string
    add_column :condominia, :latitude, :string
    add_column :condominia, :longitude, :string
    add_column :condominia, :government_plan, :boolean
    add_column :condominia, :security_features, :text
    add_column :condominia, :services, :text
    add_column :condominia, :social_features, :text
    add_column :condominia, :commercial_features, :text
    add_column :condominia, :infrastructure, :text
    add_column :condominia, :allotment_infrastructure, :text
    add_column :condominia, :leisure_features, :text
  end
end
