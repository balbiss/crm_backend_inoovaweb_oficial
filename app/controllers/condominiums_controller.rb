class CondominiumsController < ApplicationController
  before_action :set_condominium, only: %i[ show update destroy ]

  # GET /condominiums
  def index
    @condominiums = Condominium.all
    render json: @condominiums
  end

  # GET /condominiums/1
  def show
    render json: @condominium.as_json(methods: [:photo_data])
  end

  # POST /condominiums
  def create
    @condominium = Condominium.new(condominium_params)

    if @condominium.save
      if params[:photos]
        params[:photos].each do |photo|
          @condominium.photos.attach(photo)
        end
      end
      render json: @condominium, status: :created, location: @condominium
    else
      render json: @condominium.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /condominiums/1
  def update
    if params[:deleted_photo_ids]
      params[:deleted_photo_ids].each do |photo_id|
        photo = @condominium.photos.find_by(id: photo_id)
        photo.purge if photo
      end
    end

    if @condominium.update(condominium_params)
      if params[:photos]
        params[:photos].each do |photo|
          @condominium.photos.attach(photo)
        end
      end
      render json: @condominium
    else
      render json: @condominium.errors, status: :unprocessable_entity
    end
  end

  # DELETE /condominiums/1
  def destroy
    @condominium.destroy!
  end

  private
    def set_condominium
      @condominium = Condominium.find(params[:id])
    end

    def condominium_params
      params.require(:condominium).permit(
        :name, :status, :building_type, :sub_type, :construction_progress, 
        :developer, :builder, :neighborhood, :city, :state, :address, :delivery_date, 
        :account_id, :land_area, :built_area, :on_site_sales, :construction_year, 
        :administrator, :architecture, :min_price, :max_price, :tags, :condominium_types, 
        :cep, :street, :number, :country, :reference_point, :latitude, :longitude, 
        :government_plan, :security_features, :services, :social_features, 
        :commercial_features, :infrastructure, :allotment_infrastructure, :leisure_features
      )
    end
end
