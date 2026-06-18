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

    # Batch contacts: 3 GROUP BY queries instead of 9 individual COUNTs
    total_contacts  = contacts_scope.count
    temp_counts     = contacts_scope.group(:temperature).count
    status_counts   = contacts_scope.group(:status).count
    intention_counts = contacts_scope.group(:intention).count

    quente = %w[quente Quente QUENTE].sum { |t| temp_counts[t] || 0 }
    morno  = %w[morno Morno MORNO].sum   { |t| temp_counts[t] || 0 }
    frio   = %w[frio Frio FRIO].sum      { |t| temp_counts[t] || 0 }

    kanban = {
      lead:     status_counts['lead']     || 0,
      visit:    status_counts['visit']    || 0,
      proposal: status_counts['proposal'] || 0,
      won:      status_counts['won']      || 0
    }

    pretensao_venda = %w[venda Venda VENDA].sum { |i| intention_counts[i] || 0 }

    # Batch conversations: 1 GROUP BY instead of 2 COUNTs
    conv_status   = conv_scope.group(:status).count
    conv_open     = conv_status['open']     || 0
    conv_resolved = conv_status['resolved'] || 0
    conv_today    = conv_scope.where(created_at: today.beginning_of_day..today.end_of_day).count

    com_atendente_tag = account.tags.find_by(name: 'com_atendente')
    with_human = com_atendente_tag ? conv_scope.joins(:conversation_tags)
      .where(conversation_tags: { tag_id: com_atendente_tag.id }).count : 0

    # Appointments: batch status into GROUP BY
    appt_status   = appt_scope.group(:status).count
    appt_total    = appt_scope.count
    appt_today    = appt_scope.where(appointment_date: today).count
    appt_upcoming = appt_scope.where('appointment_date >= ?', today).where.not(status: 'cancelled').count
    appt_done     = appt_status['completed'] || 0

    leads_by_source = contacts_scope.where.not(source: [nil, '']).group(:source).count

    render json: {
      is_owner: is_owner,
      kpis: {
        total_contacts:  total_contacts,
        pretensao_venda: pretensao_venda,
        temperature:     { quente: quente, morno: morno, frio: frio },
        kanban:          kanban,
        conversations:   { open: conv_open, resolved: conv_resolved, today: conv_today, with_human: with_human },
        appointments:    { total: appt_total, today: appt_today, upcoming: appt_upcoming, done: appt_done }
      },
      leads_by_source: leads_by_source
    }
  end
end
