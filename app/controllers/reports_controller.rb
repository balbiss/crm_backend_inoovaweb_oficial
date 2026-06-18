class ReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_owner!

  def overview
    period = parse_period
    contacts = account.contacts.where(created_at: period)

    render json: {
      period:         { start: period.first, end: period.last },
      total_leads:    contacts.count,
      by_temperature: {
        quente: contacts.where(temperature: %w[quente Quente QUENTE]).count,
        morno:  contacts.where(temperature: %w[morno Morno MORNO]).count,
        frio:   contacts.where(temperature: %w[frio Frio FRIO]).count
      },
      by_source:   contacts.where.not(source: [nil, '']).group(:source).count,
      by_intention: contacts.where.not(intention: [nil, '']).group(:intention).count,
      funnel: {
        lead:     contacts.where(status: 'lead').count,
        visit:    contacts.where(status: 'visit').count,
        proposal: contacts.where(status: 'proposal').count,
        won:      contacts.where(status: 'won').count
      }
    }
  end

  def by_agent
    period = parse_period
    agents = account.users.where(role: 'atendente').or(account.users.where(role: 'admin'))

    data = agents.map do |agent|
      contacts   = account.contacts.where(user_id: agent.id, created_at: period)
      visits     = Appointment.where(account_id: account.id, user_id: agent.id)
                              .where(appointment_date: period.first.to_date..period.last.to_date)
      conv_open  = account.conversations.where(user_id: agent.id, status: :open).count
      conv_total = account.conversations.where(user_id: agent.id).count

      {
        id:               agent.id,
        name:             "#{agent.first_name} #{agent.last_name}".strip,
        email:            agent.email,
        leads_received:   contacts.count,
        quentes:          contacts.where(temperature: %w[quente Quente QUENTE]).count,
        visits_scheduled: visits.count,
        visits_done:      visits.where(status: 'completed').count,
        won:              contacts.where(status: 'won').count,
        open_conversations: conv_open,
        total_conversations: conv_total,
        conversion_rate:  contacts.count > 0 ? (contacts.where(status: 'won').count.to_f / contacts.count * 100).round(1) : 0
      }
    end

    render json: { period: { start: period.first, end: period.last }, agents: data }
  end

  def by_tag
    tags = account.tags.includes(:conversations)

    data = tags.map do |tag|
      contacts_with_tag = Contact.joins(conversations: :conversation_tags)
        .where(conversation_tags: { tag_id: tag.id }, contacts: { account_id: account.id })
        .distinct

      {
        id:       tag.id,
        name:     tag.name,
        color:    tag.color,
        count:    contacts_with_tag.count,
        contacts: contacts_with_tag.map do |c|
          {
            id:    c.id,
            name:  c.name.presence || "#{c.first_name} #{c.last_name}".strip,
            phone: c.phone,
            temperature: c.temperature,
            source: c.source
          }
        end
      }
    end

    render json: { tags: data }
  end

  def export
    type   = params[:type] || 'leads'
    period = parse_period

    case type
    when 'leads'
      rows = account.contacts.where(created_at: period).order(:created_at)
      csv  = generate_csv(['ID', 'Nome', 'Telefone', 'Email', 'Temperatura', 'Origem', 'Intenção', 'Status', 'Atendente', 'Criado em'],
        rows.map { |c|
          agent = c.user ? "#{c.user.first_name} #{c.user.last_name}".strip : 'Não atribuído'
          [c.id, c.name.presence || "#{c.first_name} #{c.last_name}".strip,
           c.phone, c.email, c.temperature, c.source, c.intention, c.status, agent,
           c.created_at.strftime('%d/%m/%Y %H:%M')]
        })
      filename = "leads_#{Date.current}.csv"

    when 'agents'
      by_agent_data = JSON.parse(render_to_string(action: :by_agent))['agents'] rescue []
      csv = generate_csv(['Nome', 'Email', 'Leads Recebidos', 'Quentes', 'Visitas Agendadas', 'Visitas Realizadas', 'Fechados', 'Taxa Conversão (%)'],
        by_agent_data.map { |a| [a['name'], a['email'], a['leads_received'], a['quentes'], a['visits_scheduled'], a['visits_done'], a['won'], a['conversion_rate']] })
      filename = "corretores_#{Date.current}.csv"

    when 'remarketing'
      tag_id   = params[:tag_id]
      tag      = account.tags.find_by(id: tag_id)
      contacts = Contact.joins(conversations: :conversation_tags)
        .where(conversation_tags: { tag_id: tag_id }, contacts: { account_id: account.id })
        .distinct
      csv = generate_csv(['Nome', 'Telefone', 'Temperatura', 'Origem'],
        contacts.map { |c| [c.name.presence || "#{c.first_name} #{c.last_name}".strip, c.phone, c.temperature, c.source] })
      filename = "remarketing_#{tag&.name || 'lista'}_#{Date.current}.csv"
    end

    send_data "\xEF\xBB\xBF" + csv,
      filename: filename,
      type: 'text/csv; charset=utf-8',
      disposition: 'attachment'
  end

  private

  def account
    current_user.account
  end

  def require_owner!
    unless current_user.empresa? || current_user.admin?
      render json: { error: 'Acesso restrito ao dono da imobiliária.' }, status: :forbidden
    end
  end

  def parse_period
    preset = params[:period] || 'month'
    case preset
    when 'today'
      Date.current.beginning_of_day..Date.current.end_of_day
    when 'week'
      Date.current.beginning_of_week..Date.current.end_of_week
    when 'month'
      Date.current.beginning_of_month..Date.current.end_of_month
    when 'custom'
      start_date = Date.parse(params[:start_date]) rescue Date.current.beginning_of_month
      end_date   = Date.parse(params[:end_date]) rescue Date.current
      start_date.beginning_of_day..end_date.end_of_day
    else
      Date.current.beginning_of_month..Date.current.end_of_month
    end
  end

  def generate_csv(headers, rows)
    ([headers] + rows).map { |row| row.map { |cell| "\"#{cell.to_s.gsub('"', '""')}\"" }.join(';') }.join("\n")
  end
end
