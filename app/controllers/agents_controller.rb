class AgentsController < ApplicationController
  before_action :set_agent, only: %i[ show update destroy block unblock toggle_roundrobin ]
  # Leitura liberada para todos (corretores precisam ver a equipe para atribuição).
  # Escrita restrita ao dono: criar, editar, remover, bloquear, configurar rodízio.
  before_action :require_owner!, only: %i[ create update destroy block unblock toggle_roundrobin ]

  # GET /agents
  def index
    # We list users that belong to the current user's account
    # Exclude the current user if you don't want them to see themselves (optional)
    account = current_user&.account || Account.first
    @agents = account.users.order(created_at: :desc)
    
    render json: @agents.as_json(except: [:encrypted_password, :jti],
                                  methods: [:available_for_roundrobin, :queue_position])
  end

  # GET /agents/1
  def show
    render json: @agent.as_json(except: [:encrypted_password, :jti],
                                 methods: [:available_for_roundrobin, :queue_position])
  end

  # POST /agents
  def create
    account = current_user&.account || Account.first
    @agent = account.users.build(agent_params)
    @agent.role = :atendente # Default role
    plain_password = agent_params[:password]

    if @agent.save
      WelcomeMailer.welcome(@agent, plain_password).deliver_later if @agent.email.present?
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

  # GET /agents/queue
  def queue
    account = current_user&.account || Account.first
    agents = account.users
      .where(status: 'active', available_for_roundrobin: true)
      .order(Arel.sql('queue_position ASC NULLS FIRST, id ASC'))
    render json: agents.as_json(only: [:id, :first_name, :last_name, :queue_position])
  end

  # PATCH /agents/1/toggle_roundrobin
  def toggle_roundrobin
    account = current_user&.account || Account.first

    if @agent.available_for_roundrobin?
      @agent.update!(available_for_roundrobin: false, queue_position: nil)
    else
      max_pos = account.users.where(available_for_roundrobin: true).maximum(:queue_position) || 0
      @agent.update!(available_for_roundrobin: true, queue_position: max_pos + 1)
    end

    render json: @agent.as_json(except: [:encrypted_password, :jti])
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
      params.require(:agent).permit(:first_name, :last_name, :email, :phone, :password, :status, :department, permissions: {})
    end
end
