class AgentNotificationService
  def self.notify_assignment(agent:, conversation:, assigned_by: 'sistema')
    new(agent: agent, conversation: conversation, assigned_by: assigned_by).notify
  end

  def initialize(agent:, conversation:, assigned_by:)
    @agent        = agent
    @conversation = conversation
    @assigned_by  = assigned_by
  end

  def notify
    return unless @agent.phone.present?

    inbox = @conversation.inbox
    return unless inbox.present?

    baileys = WhatsappBaileysService.new(inbox)
    return unless baileys.connected?

    jid = baileys.resolve_jid(@agent.phone)
    return Rails.logger.warn("AgentNotificationService: #{@agent.phone} não encontrado no WhatsApp") unless jid

    baileys.send_message(jid, build_message)
  rescue => e
    Rails.logger.error("AgentNotificationService error: #{e.message}")
  end

  private

  def build_message
    contact     = @conversation.contact
    name        = contact.name.presence ||
                  "#{contact.first_name} #{contact.last_name}".strip.presence ||
                  'Lead'
    intention   = contact.intention.presence
    temperature = contact.temperature.presence
    source      = contact.source.presence
    crm_url     = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
    dept       = @agent.department.presence || 'corretor'
    by_label   = case @assigned_by
                 when 'rodizio'    then 'Rodízio automático'
                 when 'ia'        then 'Encaminhado pela IA'
                 else                  'Atribuição manual'
                 end

    title = dept == 'corretor' ? "🔔 *Novo lead atribuído para você!*" : "🔔 *Nova solicitação atribuída para você!*"

    lines = []
    lines << title
    lines << ""
    lines << "👤 *Nome:* #{name}"
    lines << "🏠 *Interesse:* #{intention}"    if intention
    lines << "📍 *Origem:* #{source}"          if source
    lines << "🌡️ *Temperatura:* #{temperature.capitalize}" if temperature && dept == 'corretor'
    lines << "⚙️ _#{by_label}_"
    lines << ""
    lines << "📲 Acesse o CRM para atender:"
    lines << "#{crm_url}/conversas"
    lines << ""
    lines << "⚠️ _Atenda pelo sistema para registrar o histórico._"

    lines.join("\n")
  end
end
