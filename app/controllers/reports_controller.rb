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
    period     = parse_period
    agents     = account.users.where(role: %w[atendente admin]).to_a
    agent_ids  = agents.map(&:id)
    date_range = period.first.to_date..period.last.to_date

    # Batch: 6 queries total instead of ~8 per agent
    leads_count  = account.contacts.where(user_id: agent_ids, created_at: period).group(:user_id).count
    quentes_count = account.contacts.where(user_id: agent_ids, temperature: %w[quente Quente QUENTE], created_at: period).group(:user_id).count
    won_count    = account.contacts.where(user_id: agent_ids, status: 'won', created_at: period).group(:user_id).count
    conv_open    = account.conversations.where(user_id: agent_ids, status: :open).group(:user_id).count
    conv_total   = account.conversations.where(user_id: agent_ids).group(:user_id).count
    appt_base    = Appointment.where(account_id: account.id, user_id: agent_ids, appointment_date: date_range)
    appt_total   = appt_base.group(:user_id).count
    appt_done    = appt_base.where(status: 'completed').group(:user_id).count

    data = agents.map do |agent|
      id = agent.id
      lc = leads_count[id] || 0
      wc = won_count[id]   || 0
      {
        id:                  id,
        name:                "#{agent.first_name} #{agent.last_name}".strip,
        email:               agent.email,
        leads_received:      lc,
        quentes:             quentes_count[id] || 0,
        visits_scheduled:    appt_total[id]    || 0,
        visits_done:         appt_done[id]     || 0,
        won:                 wc,
        open_conversations:  conv_open[id]     || 0,
        total_conversations: conv_total[id]    || 0,
        conversion_rate:     lc > 0 ? (wc.to_f / lc * 100).round(1) : 0
      }
    end

    render json: { period: { start: period.first, end: period.last }, agents: data }
  end

  def by_tag
    tags    = account.tags.to_a
    tag_ids = tags.map(&:id)

    # Batch: 1 query for all tag counts instead of N
    counts = ConversationTag
      .joins(conversation: :contact)
      .where(tag_id: tag_ids, contacts: { account_id: account.id })
      .group(:tag_id)
      .count('DISTINCT contacts.id')

    data = tags.map do |tag|
      { id: tag.id, name: tag.name, color: tag.color, count: counts[tag.id] || 0 }
    end

    render json: { tags: data }
  end

  def export
    type   = params[:type] || 'leads'
    period = parse_period

    case type
    when 'leads'
      rows = account.contacts.includes(:user).where(created_at: period).order(:created_at)
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
