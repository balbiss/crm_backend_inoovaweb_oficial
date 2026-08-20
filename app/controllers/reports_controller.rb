class ReportsController < ApplicationController
  before_action :authenticate_user!
  # overview e by_tag: todos os usuários (corretor vê o funil geral da conta,
  # gerente vê só o funil da própria equipe -- ver scoped_contacts).
  # by_agent, performance e export: dono ou gerente (gerente só vê a própria
  # equipe, nunca as outras -- mesma regra do resto do app, ver
  # User#team_manager?). Corretor comum continua sem acesso a essas 3.
  before_action :require_owner_or_team_manager!, only: %i[ by_agent performance export ]

  def overview
    period = parse_period
    contacts = scoped_contacts(account.contacts.where(created_at: period))

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
    data   = by_agent_data(period)
    render json: { period: { start: period.first, end: period.last }, agents: data }
  end

  def by_tag
    tags    = account.tags.to_a
    tag_ids = tags.map(&:id)

    # Batch: 1 query for all tag counts instead of N
    tag_counts_scope = ConversationTag
      .joins(conversation: :contact)
      .where(tag_id: tag_ids, contacts: { account_id: account.id })
    tag_counts_scope = tag_counts_scope.where(conversation: { user_id: current_user.team_scope_ids }) if current_user.team_manager?
    counts = tag_counts_scope.group(:tag_id).count('DISTINCT contacts.id')

    data = tags.map do |tag|
      { id: tag.id, name: tag.name, color: tag.color, count: counts[tag.id] || 0 }
    end

    render json: { tags: data }
  end

  def performance
    conversations = scoped_conversations(account.conversations)

    # Tendência de conversas — últimos 7 dias
    conv_trend = (6.days.ago.to_date..Date.current).map do |date|
      range = date.beginning_of_day..date.end_of_day
      {
        date: date.strftime('%d/%m'),
        opened:   conversations.where(created_at: range).count,
        resolved: conversations.where(status: :resolved).where('updated_at BETWEEN ? AND ?', range.first, range.last).count
      }
    end

    # Tempo médio de primeiro atendimento (em minutos)
    sample_convs = conversations.includes(:messages).order(created_at: :desc).limit(200)
    times = sample_convs.filter_map do |conv|
      msgs = conv.messages.sort_by(&:created_at)
      first_inbound  = msgs.find { |m| m.sender_type == 'Contact' }
      first_response = msgs.find { |m| m.sender_type != 'Contact' && first_inbound && m.created_at > first_inbound.created_at }
      next unless first_inbound && first_response
      ((first_response.created_at - first_inbound.created_at) / 60.0).round(1)
    end
    avg_response = times.empty? ? nil : (times.sum / times.size).round(1)

    # Top imóveis mais consultados pela IA
    top_properties = account.properties
      .where('search_count > 0')
      .order(search_count: :desc)
      .limit(5)
      .map { |p| { id: p.id, title: p.title.presence || p.property_type, neighborhood: p.neighborhood, price: p.price, search_count: p.search_count } }

    render json: {
      conv_trend: conv_trend,
      avg_response_time_minutes: avg_response,
      top_properties: top_properties
    }
  end

  def export
    type   = params[:type] || 'leads'
    period = parse_period

    case type
    when 'leads'
      rows = scoped_contacts(account.contacts.includes(:user).where(created_at: period)).order(:created_at)
      csv  = generate_csv(['ID', 'Nome', 'Telefone', 'Email', 'Temperatura', 'Origem', 'Intenção', 'Status', 'Atendente', 'Criado em'],
        rows.map { |c|
          agent = c.user ? "#{c.user.first_name} #{c.user.last_name}".strip : 'Não atribuído'
          [c.id, c.name.presence || "#{c.first_name} #{c.last_name}".strip,
           c.phone, c.email, c.temperature, c.source, c.intention, c.status, agent,
           c.created_at.strftime('%d/%m/%Y %H:%M')]
        })
      filename = "leads_#{Date.current}.csv"

    when 'agents'
      rows = by_agent_data(period)
      csv = generate_csv(['Nome', 'Email', 'Leads Recebidos', 'Quentes', 'Visitas Agendadas', 'Visitas Realizadas', 'Fechados', 'Taxa Conversão (%)'],
        rows.map { |a| [a[:name], a[:email], a[:leads_received], a[:quentes], a[:visits_scheduled], a[:visits_done], a[:won], a[:conversion_rate]] })
      filename = "corretores_#{Date.current}.csv"

    when 'remarketing'
      tag_id   = params[:tag_id]
      tag      = account.tags.find_by(id: tag_id)
      contacts = Contact.joins(conversations: :conversation_tags)
        .where(conversation_tags: { tag_id: tag_id }, contacts: { account_id: account.id })
        .distinct
      contacts = contacts.where(conversations: { user_id: current_user.team_scope_ids }) if current_user.team_manager?
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

  # Corretor comum vê o funil geral da conta (decisão de produto já existente,
  # ver comentário no topo do arquivo) -- só restringe pra gerente, que deve
  # ver a própria equipe, nunca as outras (mesma regra de privacidade entre
  # equipes já aplicada em contacts_controller/conversations_controller/etc,
  # ver User#team_manager?). Sem isso, um gerente que ganhasse acesso às abas
  # de relatório veria dados de equipes concorrentes dentro da mesma conta.
  #
  # Importante: filtra por Conversation.user_id (via contact_id), NÃO por
  # Contact.user_id -- esse campo fica nil pra quase todo contato real (ver
  # comentário em #by_agent), então filtrar direto por ele zerava o "Visão
  # Geral" de qualquer gerente (achado real: conta DMG, 0 vs 56 contatos
  # reais da equipe). Mesmo contorno já usado em DashboardController#index.
  def scoped_contacts(base)
    return base unless current_user.team_manager?
    contact_ids = current_user.account.conversations.where(user_id: current_user.team_scope_ids).pluck(:contact_id).uniq
    base.where(id: contact_ids)
  end

  def scoped_conversations(base)
    return base.where(user_id: current_user.team_scope_ids) if current_user.team_manager?
    base
  end

  # Usado por #by_agent (JSON) e pelo export type=agents -- extraído pra
  # método reutilizável porque `render_to_string(action: :by_agent)` não
  # funciona pra reaproveitar a lógica: essa action nunca renderiza uma
  # view/template, ela só faz `render json:` direto no método, então o
  # render_to_string levantava ActionView::MissingTemplate (engolido pelo
  # `rescue []` do export) e a aba "Por Corretor" sempre baixava vazia,
  # mesmo com dados reais (confirmado ao vivo em staging: JSON tinha
  # corretores com leads, CSV vinha só com o cabeçalho).
  def by_agent_data(period)
    agents     = if current_user.full_account_access?
      account.users.where(role: %w[atendente admin]).to_a
    else
      account.users.where(role: %w[atendente admin], id: current_user.team_scope_ids).to_a
    end
    agent_ids  = agents.map(&:id)
    date_range = period.first.to_date..period.last.to_date

    # Contact.user_id não é o campo usado no fluxo real de atribuição de lead
    # (fica nil pra quase todo mundo -- achado real: conta DMG Imóveis, 485
    # de 487 contatos com Contact.user_id nil). Quem carrega o "dono do lead"
    # de verdade é Conversation.user_id (setado pelo RoundRobinAssignmentService),
    # mesmo contorno já usado em DashboardController#index. Sem isso,
    # Leads Recebidos/Quentes/Fechados/Conversão ficavam zerados pra
    # praticamente todo corretor, mesmo com conversas abertas de verdade.
    agent_by_contact = account.conversations.where(user_id: agent_ids).pluck(:contact_id, :user_id).to_h
    contacts_period   = account.contacts.where(id: agent_by_contact.keys, created_at: period).pluck(:id, :temperature, :status)

    leads_count   = Hash.new(0)
    quentes_count = Hash.new(0)
    won_count     = Hash.new(0)
    contacts_period.each do |cid, temp, status|
      aid = agent_by_contact[cid]
      leads_count[aid]   += 1
      quentes_count[aid] += 1 if %w[quente Quente QUENTE].include?(temp)
      won_count[aid]     += 1 if status == 'won'
    end

    conv_open    = account.conversations.where(user_id: agent_ids, status: :open).group(:user_id).count
    conv_total   = account.conversations.where(user_id: agent_ids).group(:user_id).count
    appt_base    = Appointment.where(account_id: account.id, user_id: agent_ids, appointment_date: date_range)
    appt_total   = appt_base.group(:user_id).count
    appt_done    = appt_base.where(status: 'completed').group(:user_id).count

    agents.map do |agent|
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
