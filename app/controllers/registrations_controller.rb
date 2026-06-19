class RegistrationsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def create
    ActiveRecord::Base.transaction do
      account = Account.create!(name: registration_params[:company_name])

      user = User.new(
        account:              account,
        role:                 :empresa,
        first_name:           registration_params[:first_name],
        last_name:            registration_params[:last_name],
        email:                registration_params[:email],
        phone:                registration_params[:phone],
        password:             registration_params[:password],
        password_confirmation: registration_params[:password_confirmation]
      )

      unless user.save
        raise ActiveRecord::RecordInvalid.new(user)
      end

      WelcomeMailer.company_welcome(user, account).deliver_later

      render json: { message: 'Conta criada com sucesso!' }, status: :created
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  def registration_params
    params.require(:registration).permit(
      :company_name, :first_name, :last_name, :email, :phone,
      :password, :password_confirmation
    )
  end
end
