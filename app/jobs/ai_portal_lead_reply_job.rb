class AiPortalLeadReplyJob < ApplicationJob
  queue_as :default

  # Substitui a antiga Thread.new crua do canal_pro_controller.rb -- rodava
  # dentro do processo web, sem sobreviver a redeploy/restart do container e
  # disputando conexão do pool do Puma com as requisições normais, o que
  # fazia a IA "sumir" silenciosamente pra uma fração real dos leads do
  # Canal Pro/OLX/ZAP/Viva Real (achado real: conta Amil, ~40% dos leads
  # recentes com telefone válido nunca receberam resposta). Como job de
  # verdade (SolidQueue), uma falha fica registrada em
  # solid_queue_failed_executions em vez de só um log perdido -- por isso
  # não tem rescue amplo aqui, deixa a exceção estourar e ficar visível.
  RETRY_WAITS = [0, 5, 15].freeze

  def perform(account_id, inbox_id, conversation_id, contact_id, phone, established_jid, raw_jid, extra_context)
    account      = Account.find_by(id: account_id)
    inbox        = Inbox.find_by(id: inbox_id)
    conversation = Conversation.find_by(id: conversation_id)
    contact      = Contact.find_by(id: contact_id)
    return unless account && inbox && conversation && contact

    baileys_service = WhatsappBaileysService.new(inbox)
    jid = established_jid.presence || baileys_service.resolve_jid(phone) || raw_jid
    contact.update_column(:jid, jid) if contact.jid != jid

    ai_service = AiAssistantService.new(inbox, conversation, extra_context: extra_context)
    ai_response = ai_service.process_message
    return if ai_response.blank?

    Rails.cache.write("ai_is_replying_#{inbox.id}_#{jid}", true, expires_in: 60.seconds)

    paragraphs = ai_response.is_a?(Array) ? ai_response : ai_response.split("\n\n").reject(&:blank?)
    paragraphs.each do |para|
      baileys_id = send_message_with_retry(baileys_service, jid, para.strip)
      Message.create!(
        account:      account,
        conversation: conversation,
        text:         para.strip,
        sender_type:  'User',
        sender_id:    nil,
        source_id:    baileys_id.presence || "ai_#{SecureRandom.hex(8)}",
        status:       baileys_id.present? ? :delivered : :failed
      )
    end
  end

  private

  # Mesmo retry curto que já existia inline no controller (cobre instabilidade
  # conhecida de conexão do Baileys, stream errors 503/515).
  def send_message_with_retry(baileys_service, jid, text)
    RETRY_WAITS.each do |wait_seconds|
      sleep wait_seconds if wait_seconds.positive?
      begin
        baileys_id = baileys_service.send_message(jid, text)
        return baileys_id if baileys_id.present?
      rescue => e
        Rails.logger.warn("AiPortalLeadReplyJob: tentativa de envio falhou (#{e.message})")
      end
    end
    Rails.logger.error("AiPortalLeadReplyJob: desistiu após 3 tentativas, jid=#{jid}")
    nil
  end
end
