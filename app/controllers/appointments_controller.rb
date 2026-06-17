class AppointmentsController < ApplicationController
  before_action :set_appointment, only: %i[ show update destroy ]

  # GET /appointments
  def index
    if current_user&.role == 'admin' || current_user&.role == 'empresa' || current_user&.permissions&.dig('view_all_appointments')
      @appointments = Appointment.includes(:contact, :property).all
    else
      @appointments = Appointment.includes(:contact, :property).where(user_id: current_user.id)
    end
    
    render json: @appointments.as_json(include: {
      contact: { only: [:name, :phone] },
      property: { only: [:title, :id] }
    })
  end

  # GET /appointments/1
  def show
    render json: @appointment.as_json(include: {
      contact: { only: [:name, :phone] },
      property: { only: [:title, :id] }
    })
  end

  # POST /appointments
  def create
    # Try to use current_user's account, fallback to first account or 1 if not available
    account = current_user&.account || Account.first || Account.new(id: 1)
    
    @appointment = Appointment.new(appointment_params)
    @appointment.account_id ||= account.id
    @appointment.user_id ||= current_user.id

    if @appointment.save
      render json: @appointment, status: :created, location: @appointment
    else
      render json: @appointment.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /appointments/1
  def update
    if @appointment.update(appointment_params)
      render json: @appointment
    else
      render json: @appointment.errors, status: :unprocessable_entity
    end
  end

  # DELETE /appointments/1
  def destroy
    @appointment.destroy!
  end

  private
    def set_appointment
      @appointment = Appointment.find(params[:id])
    end

    def appointment_params
      params.require(:appointment).permit(:account_id, :contact_id, :property_id, :broker_name, :status, :appointment_date, :start_time, :end_time)
    end
end
