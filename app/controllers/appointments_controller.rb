class AppointmentsController < ApplicationController
  before_action :set_appointment, only: %i[ show update destroy ]

  # GET /appointments/report
  def report
    scope  = base_scope.includes(:contact, :property, :user)
    period = parse_period(params[:period])
    scoped = scope.where(appointment_date: period)

    by_status = {
      pending:   scoped.where(status: %w[pending agendado]).count,
      confirmed: scoped.where(status: %w[confirmed confirmado]).count,
      completed: scoped.where(status: %w[completed realizado]).count,
      cancelled: scoped.where(status: %w[cancelled cancelado]).count
    }

    by_agent = if owner?
      current_user.account.users.where(role: %w[atendente admin]).map do |agent|
        agent_scope = scoped.where(user_id: agent.id)
        {
          id:    agent.id,
          name:  "#{agent.first_name} #{agent.last_name}".strip,
          total: agent_scope.count,
          done:  agent_scope.where(status: %w[completed realizado]).count
        }
      end
    else
      nil
    end

    appointments = scoped.order(appointment_date: :asc).map do |a|
      {
        id:               a.id,
        status:           a.status,
        appointment_date: a.appointment_date,
        start_time:       a.start_time,
        end_time:         a.end_time,
        contact:          { name: a.contact&.name, phone: a.contact&.phone },
        property:         { title: a.property&.title },
        agent:            a.user ? "#{a.user.first_name} #{a.user.last_name}".strip : nil
      }
    end

    render json: {
      is_owner:     owner?,
      period:       { start: period.first, end: period.last },
      total:        scoped.count,
      by_status:    by_status,
      by_agent:     by_agent,
      appointments: appointments
    }
  end

  # GET /appointments/export
  def export
    scope  = base_scope.includes(:contact, :property, :user)
    period = parse_period(params[:period])
    rows   = scope.where(appointment_date: period).order(appointment_date: :asc)

    headers_row = ['Data', 'Início', 'Fim', 'Cliente', 'Telefone', 'Imóvel', 'Corretor', 'Status']
    csv_rows = rows.map do |a|
      [
        a.appointment_date&.strftime('%d/%m/%Y'),
        a.start_time, a.end_time,
        a.contact&.name, a.contact&.phone,
        a.property&.title,
        a.user ? "#{a.user.first_name} #{a.user.last_name}".strip : 'N/A',
        a.status
      ]
    end

    csv = ([headers_row] + csv_rows).map { |r| r.map { |c| "\"#{c.to_s.gsub('"','""')}\"" }.join(';') }.join("\n")
    send_data "\xEF\xBB\xBF" + csv,
      filename: "agendamentos_#{Date.current}.csv",
      type: 'text/csv; charset=utf-8',
      disposition: 'attachment'
  end

  # GET /appointments
  def index
    account_id = current_user.account_id
    scope = Appointment.includes(:contact, :property).where(account_id: account_id)

    unless owner? || current_user.has_permission?('view_all_appointments')
      scope = scope.where(user_id: [current_user.id, nil])
    end

    render json: scope.as_json(include: {
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
    @appointment = Appointment.new(appointment_params)
    @appointment.account_id = current_user.account_id
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
    def owner?
      current_user.empresa? || current_user.admin?
    end

    def base_scope
      account = current_user.account
      if owner?
        Appointment.where(account_id: account.id)
      else
        Appointment.where(account_id: account.id, user_id: current_user.id)
      end
    end

    def parse_period(preset)
      case preset
      when 'today' then Date.current.beginning_of_day..Date.current.end_of_day
      when 'week'  then Date.current.beginning_of_week..Date.current.end_of_week
      when 'month' then Date.current.beginning_of_month..Date.current.end_of_month
      when 'custom'
        s = Date.parse(params[:start_date]) rescue Date.current.beginning_of_month
        e = Date.parse(params[:end_date])   rescue Date.current
        s.beginning_of_day..e.end_of_day
      else
        Date.current.beginning_of_month..Date.current.end_of_month
      end
    end

    def set_appointment
      @appointment = current_user.account.appointments.find(params[:id])
    end

    def appointment_params
      params.require(:appointment).permit(:account_id, :contact_id, :property_id, :broker_name, :status, :appointment_date, :start_time, :end_time)
    end
end
