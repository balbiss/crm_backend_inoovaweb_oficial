class PropertiesController < ApplicationController
  before_action :set_property, only: %i[ show update destroy ]

  # GET /properties
  def index
    @properties = current_user.account.properties.with_attached_photos.order(created_at: :desc)
    render json: @properties.as_json(methods: [:photo_urls])
  end

  # GET /properties/1
  def show
    render json: @property.as_json(methods: [:photo_data])
  end

  # POST /properties
  def create
    @property = current_user.account.properties.build(property_params)
    
    if params[:photos]
      params[:photos].each do |photo|
        @property.photos.attach(photo)
      end
    end

    if @property.save
      render json: @property.as_json(methods: [:photo_urls]), status: :created, location: @property
    else
      render json: @property.errors, status: :unprocessable_content
    end
  end

  # PATCH/PUT /properties/1
  def update
    if params[:deleted_photo_ids]
      params[:deleted_photo_ids].each do |photo_id|
        photo = @property.photos.find_by(id: photo_id)
        photo.purge if photo
      end
    end

    if @property.update(property_params)
      if params[:photos]
        params[:photos].each do |photo|
          @property.photos.attach(photo)
        end
      end
      render json: @property.as_json(methods: [:photo_urls])
    else
      render json: @property.errors, status: :unprocessable_content
    end
  end

  # DELETE /properties/1
  def destroy
    @property.destroy!
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_property
      @property = current_user.account.properties.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def property_params
      params.require(:property).permit(
        :title, :description, :price, :status, 
        :code, :owner_name, :owner_email, :owner_phone, :owner_phone_type,
        :usage_type, :property_type, :condo_name, :cep, :street, :number,
        :neighborhood, :city, :state, :country, :complement, :reference_point,
        :latitude, :longitude, :show_address_mode, :listing_type, :iptu_condition,
        :iptu_value, :exclusivity, :auth_start_date, :auth_end_date,
        :built_area, :total_area, :suites, :bedrooms, :bathrooms, :parking_spots,
        :agent_name, :agent_phone
      )
    end
end
