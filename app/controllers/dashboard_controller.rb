class DashboardController < ApplicationController
  def index
    is_owner   = current_user.empresa? || current_user.admin? || current_user.has_permission?('view_all_contacts')
    account    = current_user.account
    uid        = current_user.id
    today      = Date.current

    # Scopes filtrados por papel
    contacts_scope = is_owner ? account.contacts : account.contacts.where(user_id: uid)
    conv_scope     = is_owner ? account.conversations : account.conversations.where(user_id: uid)
    appt_scope     = is_owner ? Appointment.where(account_id: account.id) : Appointment.where(account_id: account.id, user_id: uid)

    # === KPIs de Contatos ===
    total_contacts = contacts_scope.count
    quente = contacts_scope.where(temperature: %w[quente Quente QUENTE]).count
    morno  = contacts_scope.where(temperature: %w[morno Morno MORNO]).count
    frio   = contacts_scope.where(temperature: %w[frio Frio FRIO]).count

    # === Funil Kanban ===
    kanban = {
      lead:     contacts_scope.where(status: 'lead').count,
      visit:    contacts_scope.where(status: 'visit').count,
      proposal: contacts_scope.where(status: 'proposal').count,
      won:      contacts_scope.where(status: 'won').count
    }

    # === Conversas ===
    conv_open     = conv_scope.where(status: :open).count
    conv_resolved = conv_scope.where(status: :resolved).count
    conv_today    = conv_scope.where(created_at: today.beginning_of_day..today.end_of_day).count

    # Leads em atendimento humano (com tag com_atendente)
    com_atendente_tag = account.tags.find_by(name: 'com_atendente')
    with_human = com_atendente_tag ? conv_scope.joins(:conversation_tags)
      .where(conversation_tags: { tag_id: com_atendente_tag.id }).count : 0

    # === Agendamentos ===
    appt_total    = appt_scope.count
    appt_today    = appt_scope.where(appointment_date: today).count
    appt_upcoming = appt_scope.where('appointment_date >= ?', today).where.not(status: 'cancelled').count
    appt_done     = appt_scope.where(status: 'completed').count

    # === Leads por fonte ===
    leads_by_source = contacts_scope.where.not(source: [nil, '']).group(:source).count

    render json: {
      is_owner: is_owner,
      kpis: {
        total_contacts:   total_contacts,
        pretensao_venda:  contacts_scope.where(intention: %w[venda Venda VENDA]).count,
        temperature:      { quente: quente, morno: morno, frio: frio },
        kanban:           kanban,
        conversations:    { open: conv_open, resolved: conv_resolved, today: conv_today, with_human: with_human },
        appointments:     { total: appt_total, today: appt_today, upcoming: appt_upcoming, done: appt_done }
      },
      leads_by_source: leads_by_source
    }
  end
end
