class TagsController < ApplicationController
  before_action :set_tag, only: %i[ update destroy ]

  # GET /tags
  def index
    @tags = current_user.account.tags.order(name: :asc)
    render json: @tags
  end

  # POST /tags
  def create
    @tag = current_user.account.tags.build(tag_params)

    if @tag.save
      render json: @tag, status: :created
    else
      render json: @tag.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /tags/1
  def update
    if @tag.update(tag_params)
      render json: @tag
    else
      render json: @tag.errors, status: :unprocessable_entity
    end
  end

  # DELETE /tags/1
  def destroy
    @tag.destroy!
  end

  private
    def set_tag
      @tag = current_user.account.tags.find(params[:id])
    end

    def tag_params
      params.require(:tag).permit(:name, :color)
    end
end
