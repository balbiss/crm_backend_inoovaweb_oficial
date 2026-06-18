class RoundRobinAssignmentService
  # Assigns the next available agent in the round-robin queue to a conversation.
  # Returns the assigned User or nil if no eligible agent exists.
  def self.assign_next(conversation)
    return nil if conversation.user_id.present?

    assigned_agent = nil

    ApplicationRecord.transaction do
      account = conversation.account.lock!

      agent = User
        .where(account_id: account.id, status: 'active', available_for_roundrobin: true)
        .order(Arel.sql('queue_position ASC NULLS FIRST, id ASC'))
        .lock
        .first

      return nil unless agent

      max_pos = User.where(account_id: account.id, available_for_roundrobin: true)
                    .maximum(:queue_position) || 0
      agent.update_columns(queue_position: max_pos + 1)

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
    ActionCable.server.broadcast('conversations_channel', {
      event: 'conversation_updated',
      conversation: {
        id: conversation.id,
        assignee_id: agent.id,
        assignee: agent.first_name
      }
    })

    ActionCable.server.broadcast('conversations_channel', {
      event: 'lead_atribuido',
      assigned_to_user_id: agent.id,
      conversation_id: conversation.id,
      contact_name: conversation.contact.name.presence || conversation.contact.phone,
      assigned_by: 'rodizio'
    })
  end
end
