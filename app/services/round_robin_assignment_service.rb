class RoundRobinAssignmentService
  # Assigns the next available agent in the round-robin queue to a conversation.
  # Returns the assigned User or nil if no eligible agent exists.
  def self.assign_next(conversation)
    return nil if conversation.user_id.present?

    assigned_agent = nil

    ApplicationRecord.transaction do
      account = conversation.account.lock!
      group_id = conversation.inbox&.round_robin_group_id || group_id_from_purpose(account, conversation)

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

  # Público: usado pela IA pra saber se precisa perguntar "compra ou locação"
  # ANTES de prometer a transferência, quando a conta tem roletas separadas
  # por finalidade numa mesma inbox e ainda não há nenhum sinal (nem
  # 'qualify_lead', nem palavra-chave no que o lead escreveu) de qual das
  # duas equipes é a certa -- sem essa pergunta, group_id_from_purpose cai
  # pro pool sem filtro (as duas equipes juntas) e o lead pode cair com o
  # corretor errado (achado real: conta Amil, conversas #2378 e #2500, ambas
  # transferidas na primeira resposta da IA, antes de qualquer sinal de
  # compra/locação existir, e caindo por sorte/azar numa equipe ou outra).
  def self.ambiguous_pending_purpose?(conversation)
    return false if conversation.user_id.present?
    return false if conversation.inbox&.round_robin_group_id.present?
    return false if conversation.account.round_robin_groups.count < 2
    group_id_from_purpose(conversation.account, conversation).nil?
  end

  private

  # Contas que atendem venda e locação pelo MESMO número de WhatsApp não
  # conseguem separar as roletas só pelo inbox (um inbox só, duas equipes).
  # Nesse caso, usa a intenção que a IA já captura via 'qualify_lead' (args
  # 'purpose': compra/locacao) pra escolher o grupo certo -- resolvido por
  # nome do grupo (contém "venda" ou "loca") em vez de id fixo, já que cada
  # conta nomeia as roletas do seu jeito. Achado real: conta Amil Negócios
  # Imobiliários, um WhatsApp só recebendo os dois tipos de lead, mas com
  # roletas "VENDAS" e "LOCAÇÃO" separadas -- sem isso, o lead podia cair
  # com um corretor de locação forçado a atender venda (ou vice-versa).
  def self.group_id_from_purpose(account, conversation)
    contact = conversation.contact
    purpose = contact&.custom_attributes&.dig('purpose')

    # 'purpose' só existe se a IA chamou 'qualify_lead' antes de transferir --
    # como isso depende de tool_choice:auto (probabilístico, mesma classe de
    # problema já resolvida pra 'com_atendente' via trava determinística),
    # às vezes a IA promete/transfere sem nunca ter chamado 'qualify_lead'.
    # Sem esse fallback o lead cai sem filtro de grupo nenhum (primeiro da
    # fila entre AS DUAS equipes), o que na prática sempre caía na roleta de
    # VENDAS (achado real: conta Amil, grupo VENDAS com mais gente na fila
    # do que LOCAÇÃO). Último recurso: procura palavra-chave óbvia de
    # locação/venda direto no que o próprio lead escreveu.
    if purpose.blank?
      lead_text = conversation.messages.where(sender_type: 'Contact').pluck(:text).join(' ')
      purpose = if lead_text.match?(/alug|loca[çc][aã]o|\blocar\b/i)
        'locacao'
      elsif lead_text.match?(/\bcomprar\b|\bcompra\b|\bvenda\b|\bfinanciar\b/i)
        'compra'
      end
    end
    return nil if purpose.blank?

    pattern = purpose == 'locacao' ? /loca/i : /venda|compra/i
    account.round_robin_groups.find { |g| g.name.to_s.match?(pattern) }&.id
  end

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
