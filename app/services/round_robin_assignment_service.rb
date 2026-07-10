class RoundRobinAssignmentService
  # Assigns the next available agent in the round-robin queue to a conversation.
  # Returns the assigned User or nil if no eligible agent exists.
  def self.assign_next(conversation)
    return nil if conversation.user_id.present?

    assigned_agent = nil

    ApplicationRecord.transaction do
      account = conversation.account.lock!
      group_id = conversation.inbox&.round_robin_group_id

      base_scope = User.where(account_id: account.id, status: 'active', department: 'corretor')
      base_scope = base_scope.where(round_robin_group_id: group_id) if group_id.present?

      agent = base_scope
        .where(available_for_roundrobin: true)
        .order(Arel.sql('queue_position ASC NULLS FIRST, id ASC'))
        .lock
        .first

      # Fallback: se ninguém está na fila de rodízio (ex: conta com um único
      # corretor que nunca teve o toggle ativado), ainda assim atribui para
      # algum corretor ativo do grupo (ou da conta, se o inbox não tiver
      # grupo definido) em vez de deixar o lead sem ninguém.
      agent ||= base_scope
        .order(:id)
        .lock
        .first

      return nil unless agent

      if agent.available_for_roundrobin
        max_pos = User.where(account_id: account.id, available_for_roundrobin: true)
                      .maximum(:queue_position) || 0
        agent.update_columns(queue_position: max_pos + 1)
      end

      conversation.update!(user_id: agent.id)
      assigned_agent = agent
    end

    if assigned_agent
      broadcast_assignment(conversation, assigned_agent)
      AgentNotificationService.notify_assignment(
        agent:       assigned_agent,
        conversation: conversation,
        assigned_by: 'rodizio'
      )
    end

    assigned_agent
  rescue => e
    Rails.logger.error("RoundRobinAssignmentService error: #{e.message}")
    nil
  end

  private

  def self.broadcast_assignment(conversation, agent)
    ActionCable.server.broadcast("conversations_channel_#{conversation.account_id}", {
      event: 'conversation_updated',
      conversation: {
        id: conversation.id,
        assignee_id: agent.id,
        assignee: agent.first_name
      }
    })

    ActionCable.server.broadcast("conversations_channel_#{conversation.account_id}", {
      event: 'lead_atribuido',
      assigned_to_user_id: agent.id,
      conversation_id: conversation.id,
      contact_name: conversation.contact.name.presence || conversation.contact.phone,
      assigned_by: 'rodizio'
    })
  end
end
