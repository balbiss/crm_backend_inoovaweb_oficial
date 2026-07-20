class RoundRobinGroupsController < ApplicationController
  # Leitura liberada pro gerente também (precisa ver o nome da própria equipe
  # na tela de Agentes). Criar/renomear/excluir grupo continua exclusivo do dono.
  before_action :require_owner!, except: %i[ index ]
  before_action :require_owner_or_team_manager!, only: %i[ index ]
  before_action :set_round_robin_group, only: %i[ update destroy ]

  # GET /round_robin_groups
  def index
    account = current_user&.account || Account.first
    @groups = account.round_robin_groups.order(:name)
    render json: @groups
  end

  # POST /round_robin_groups
  def create
    account = current_user&.account || Account.first
    @group = account.round_robin_groups.build(round_robin_group_params)

    if @group.save
      render json: @group, status: :created
    else
      render json: @group.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /round_robin_groups/1
  def update
    if @group.update(round_robin_group_params)
      render json: @group
    else
      render json: @group.errors, status: :unprocessable_entity
    end
  end

  # DELETE /round_robin_groups/1
  def destroy
    @group.destroy
    head :no_content
  end

  private
    def set_round_robin_group
      account = current_user&.account || Account.first
      @group = account.round_robin_groups.find(params[:id])
    end

    def round_robin_group_params
      params.require(:round_robin_group).permit(:name)
    end
end
