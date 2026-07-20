class DashboardController < ApplicationController
  def index
    is_owner   = current_user.full_account_access? || (current_user.has_permission?('view_all_contacts') && !current_user.team_manager?)
    account    = current_user.account
    uids       = current_user.team_scope_ids
    today      = Date.current

    # Scopes filtrados por papel
    # Corretor: contatos derivados das conversas atribuídas a ele (não user_id do contato)
    # Gerente: mesma lógica, mas `uids` já cobre toda a equipe (ver User#team_scope_ids)
    if is_owner
      contacts_scope = account.contacts
      conv_scope     = account.conversations
      appt_scope     = Appointment.where(account_id: account.id)
    else
      my_contact_ids = account.conversations.where(user_id: uids).pluck(:contact_id).uniq
      contacts_scope = account.contacts.where(id: my_contact_ids)
      conv_scope     = account.conversations.where(user_id: uids)
      # Agendamentos atribuídos ao corretor/equipe OU criados pela IA para seus contatos
      appt_scope     = Appointment.where(account_id: account.id)
                                  .where('user_id IN (?) OR (user_id IS NULL AND contact_id IN (?))', uids, my_contact_ids.presence || [0])
    end

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

    # Leads atribuídos hoje — conversas novas atribuídas a este usuário (ou a qualquer um, se dono)
    today_conv_scope = is_owner \
      ? account.conversations.where(created_at: today.beginning_of_day..today.end_of_day) \
      : account.conversations.where(user_id: uids, created_at: today.beginning_of_day..today.end_of_day)

    today_assigned_leads = today_conv_scope
      .includes(:contact)
      .order(created_at: :desc)
      .limit(20)
      .map do |conv|
        c = conv.contact
        next unless c
        {
          conversation_id: conv.id,
          contact_name:    c.name.presence || c.phone || 'Desconhecido',
          contact_phone:   c.phone,
          temperature:     c.temperature,
          kanban_status:   c.status,
          intention:       c.intention&.truncate(80),
          assigned_to:     conv.user_id == current_user.id ? nil : account.users.find_by(id: conv.user_id)&.first_name,
          created_at:      conv.created_at
        }
      end.compact

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
      leads_by_source:      leads_by_source,
      today_assigned_leads: today_assigned_leads
    }
  end
end
