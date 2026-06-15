class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  skip_before_action :check_subscription_access!

  private

  def require_admin!
    unless current_user.admin?
      render json: { error: 'Acesso Negado. Esta área é restrita a administradores do sistema.' }, status: :forbidden
    end
  end
end
