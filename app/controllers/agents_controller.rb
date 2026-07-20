class AgentsController < ApplicationController
  before_action :set_agent, only: %i[ show update destroy block unblock toggle_roundrobin ]
  # Leitura liberada para todos (corretores precisam ver a equipe para atribuição).
  # Escrita liberada pro dono (sem restrição). Gerente também pode criar/editar/
  # bloquear/(des)ativar no rodízio -- mas só corretores da própria equipe, e
  # exclusão permanente continua exclusiva do dono (require_owner!).
  before_action :require_owner!, only: %i[ destroy ]
  before_action :require_owner_or_team_manager!, only: %i[ create update block unblock toggle_roundrobin ]
  before_action :require_same_team!, only: %i[ update block unblock toggle_roundrobin ], unless: :owner?

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

    # Gerente só cadastra corretor pra própria equipe -- ignora department/
    # grupo/permissões que vierem no payload e força os valores certos.
    unless owner?
      if current_user.round_robin_group_id.blank?
        return render json: { error: 'sem_equipe', message: 'Você precisa estar vinculado a uma equipe (grupo de rodízio) para cadastrar corretores.' }, status: :unprocessable_entity
      end
      @agent.department = 'corretor'
      @agent.round_robin_group_id = current_user.round_robin_group_id
      @agent.permissions = {}
    end

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

    # Gerente não pode mover o corretor pra outra equipe, promovê-lo a
    # gerente/admin nem conceder permissões especiais.
    unless owner?
      prms[:department] = 'corretor'
      prms[:round_robin_group_id] = current_user.round_robin_group_id
      prms.delete(:permissions)
    end

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
    if @agent.destroy
      head :no_content
    else
      render json: { error: @agent.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private
    def set_agent
      account = current_user&.account || Account.first
      @agent = account.users.find(params[:id])
    end

    # Gerente só pode gerenciar corretores da própria equipe -- nunca outro
    # gerente/admin, nem corretor de outra equipe.
    def require_same_team!
      same_team = @agent.department == 'corretor' &&
                  @agent.round_robin_group_id.present? &&
                  @agent.round_robin_group_id == current_user.round_robin_group_id
      return if same_team

      render json: { error: 'forbidden', message: 'Você só pode gerenciar corretores da sua própria equipe.' }, status: :forbidden
    end

    def agent_params
      params.require(:agent).permit(:first_name, :last_name, :email, :phone, :password, :status, :department, :round_robin_group_id, permissions: {})
    end
end
