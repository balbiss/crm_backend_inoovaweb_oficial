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

    baileys.send_message(@agent.phone, build_message)
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
    by_label    = @assigned_by == 'rodizio' ? 'Rodízio automático' : 'Atribuição manual'

    lines = []
    lines << "🔔 *Novo lead atribuído para você!*"
    lines << ""
    lines << "👤 *Nome:* #{name}"
    lines << "🏠 *Interesse:* #{intention}"    if intention
    lines << "📍 *Origem:* #{source}"          if source
    lines << "🌡️ *Temperatura:* #{temperature.capitalize}" if temperature
    lines << "⚙️ _#{by_label}_"
    lines << ""
    lines << "📲 Acesse o CRM para atender:"
    lines << "#{crm_url}/conversas"
    lines << ""
    lines << "⚠️ _Atenda pelo sistema para registrar o histórico._"

    lines.join("\n")
  end
end
