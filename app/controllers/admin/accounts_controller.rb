class Admin::AccountsController < Admin::BaseController
  def index
    # Retorna todas as contas com dados do proprietário principal
    accounts = Account.all.map do |account|
      owner = account.users.where(role: :empresa).first || account.users.first
      {
        id: account.id,
        name: account.name,
        created_at: account.created_at,
        subscription_status: account.subscription_status,
        trial_ends_at: account.trial_ends_at,
        owner_email: owner&.email,
        owner_name: "#{owner&.first_name} #{owner&.last_name}".strip
      }
    end

    render json: accounts
  end

  def create
    ActiveRecord::Base.transaction do
      account = Account.create!(account_params)
      
      user_params_to_save = user_params.merge(
        account: account,
        role: :empresa
      )
      
      user = User.create!(user_params_to_save)
      
      render json: { message: 'Empresa criada com sucesso!', id: account.id }, status: :created
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    account = Account.find(params[:id])
    owner = account.users.where(role: :empresa).first || account.users.first

    ActiveRecord::Base.transaction do
      account.update!(account_params) if account_params.present?
      
      if user_params.present? && owner
        # Ignora senha se estiver em branco
        u_params = user_params.to_h
        u_params.delete(:password) if u_params[:password].blank?
        owner.update!(u_params)
      end
      
      render json: { message: 'Conta atualizada com sucesso.' }
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    account = Account.find(params[:id])
    account.destroy
    render json: { message: 'Conta e todos os dados associados foram excluídos.' }
  end

  def block
    account = Account.find(params[:id])
    account.update(subscription_status: 'blocked')
    render json: { message: 'Acesso da empresa foi bloqueado.' }
  end

  private

  def account_params
    params.require(:account).permit(:name, :subscription_status, :trial_ends_at)
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email, :password)
  end
end
