class Users::RegistrationsController < Devise::RegistrationsController
  respond_to :json

  def create
    build_resource(sign_up_params)

    ActiveRecord::Base.transaction do
      # Cria a empresa com Trial de 7 dias
      company_name = params[:user][:company_name] || "Imobiliária #{resource.first_name}"
      @account = Account.create!(
        name: company_name,
        subscription_status: 'trialing',
        trial_ends_at: 7.days.from_now
      )

      resource.account = @account
      resource.role = :empresa # O primeiro usuário é o dono da empresa
      resource.save!
    end

    if resource.persisted?
      if resource.active_for_authentication?
        # sign_up(resource_name, resource) # Removed because we are in API mode without sessions
        render json: { message: "Conta criada com sucesso", user: resource, account: @account }, status: :created
      else
        expire_data_after_sign_in!
        render json: { message: "Conta criada. #{resource.inactive_message}" }, status: :created
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      render json: { errors: resource.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  end

  private

  def sign_up_params
    params.require(:user).permit(:email, :password, :password_confirmation, :first_name, :last_name)
  end
end
