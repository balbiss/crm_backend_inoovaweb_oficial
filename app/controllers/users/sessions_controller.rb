class Users::SessionsController < Devise::SessionsController
  respond_to :json

  private

  def respond_with(resource, _opts = {})
    render json: {
      message: 'Login bem-sucedido.',
      user: {
        id: resource.id,
        email: resource.email,
        first_name: resource.first_name,
        last_name: resource.last_name,
        role: resource.role,
        account_id: resource.account_id,
        account_name: resource.account&.name
      }
    }, status: :ok
  end

  def respond_to_on_destroy
    if current_user
      render json: {
        message: 'Logout realizado com sucesso.'
      }, status: :ok
    else
      render json: {
        message: 'Nenhum usuário ativo para fazer logout.'
      }, status: :unauthorized
    end
  end
end
