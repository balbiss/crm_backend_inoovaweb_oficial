class AgentsController < ApplicationController
  before_action :set_agent, only: %i[ show update destroy block unblock ]

  # GET /agents
  def index
    # We list users that belong to the current user's account
    # Exclude the current user if you don't want them to see themselves (optional)
    account = current_user&.account || Account.first
    @agents = account.users.order(created_at: :desc)
    
    render json: @agents.as_json(except: [:encrypted_password, :jti])
  end

  # GET /agents/1
  def show
    render json: @agent.as_json(except: [:encrypted_password, :jti])
  end

  # POST /agents
  def create
    account = current_user&.account || Account.first
    @agent = account.users.build(agent_params)
    @agent.role = :atendente # Default role

    if @agent.save
      render json: @agent.as_json(except: [:encrypted_password, :jti]), status: :created
    else
      render json: @agent.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /agents/1
  def update
    prms = agent_params
    # If password is blank, don't update it
    prms.delete(:password) if prms[:password].blank?

    if @agent.update(prms)
      render json: @agent.as_json(except: [:encrypted_password, :jti])
    else
      render json: @agent.errors, status: :unprocessable_entity
    end
  end

  # PATCH /agents/1/block
  def block
    if @agent.update(status: 'blocked')
      render json: { message: 'Agent blocked' }
    else
      render json: @agent.errors, status: :unprocessable_entity
    end
  end

  # PATCH /agents/1/unblock
  def unblock
    if @agent.update(status: 'active')
      render json: { message: 'Agent unblocked' }
    else
      render json: @agent.errors, status: :unprocessable_entity
    end
  end

  # DELETE /agents/1
  def destroy
    @agent.destroy
  end

  private
    def set_agent
      account = current_user&.account || Account.first
      @agent = account.users.find(params[:id])
    end

    def agent_params
      params.require(:agent).permit(:first_name, :last_name, :email, :phone, :password, :status, permissions: {})
    end
end
