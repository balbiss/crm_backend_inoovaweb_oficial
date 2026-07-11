require 'net/http'
require 'uri'
require 'json'
require 'cgi'

class InstagramMessagingService
  GRAPH_API_VERSION = 'v21.0'.freeze

  def initialize(inbox)
    @inbox = inbox
    @ig_user_id = inbox.instagram_business_account_id
    @access_token = inbox.instagram_access_token
  end

  # A Graph API do Instagram não suporta legenda junto do anexo (diferente do
  # Baileys) — se vier texto E anexo, manda duas mensagens separadas; o
  # source_id retornado (usado pro dedup) é sempre o da última mensagem enviada.
  def send_message(recipient_igsid, text, attachment = nil)
    message_id = nil
    message_id = send_text(recipient_igsid, text) if text.present?
    message_id = send_attachment(recipient_igsid, attachment) if attachment.present?
    message_id
  rescue => e
    Rails.logger.error("InstagramMessagingService send_message error: #{e.message}")
    nil
  end

  def send_presence_update(recipient_igsid, presence = 'composing')
    sender_action = presence == 'composing' ? 'typing_on' : 'typing_off'
    response = post_to_graph({ recipient: { id: recipient_igsid }, sender_action: sender_action })
    response.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.error("InstagramMessagingService send_presence_update error: #{e.message}")
    false
  end

  def resolve_jid(_phone)
    nil
  end

  def fetch_profile_picture_url(igsid)
    uri = URI.parse("https://graph.instagram.com/#{GRAPH_API_VERSION}/#{igsid}?fields=profile_pic&access_token=#{CGI.escape(@access_token.to_s)}")
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.get(uri) }
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)['profile_pic']
  rescue => e
    Rails.logger.error("InstagramMessagingService fetch_profile_picture_url error: #{e.message}")
    nil
  end

  def connected?
    @access_token.present? && (@inbox.instagram_token_expires_at.nil? || @inbox.instagram_token_expires_at.future?)
  end

  # Instagram não usa pareamento/QR — a conexão já é estabelecida via OAuth.
  def create_connection(_webhook_url)
    true
  end

  def delete_connection
    @inbox.update(instagram_access_token: nil, instagram_token_expires_at: nil)
    true
  end

  # Não implementado nesta rodada (upload de anexo binário direto) — attachments
  # são enviados via URL pública (ver #attachment_payload), diferente do Baileys.
  def send_raw_document(_igsid, filename:, mimetype:, data:, caption: nil)
    false
  end

  def send_raw_image(_igsid, data:, caption: nil)
    false
  end

  private

  def send_text(recipient_igsid, text)
    response = post_to_graph({ recipient: { id: recipient_igsid }, message: { text: text } })
    return nil unless response.is_a?(Net::HTTPSuccess)

    (JSON.parse(response.body) rescue {})['message_id']
  end

  def send_attachment(recipient_igsid, attachment)
    response = post_to_graph({ recipient: { id: recipient_igsid }, message: { attachment: attachment_payload(attachment) } })
    return nil unless response.is_a?(Net::HTTPSuccess)

    (JSON.parse(response.body) rescue {})['message_id']
  end

  def attachment_payload(attachment)
    url = Rails.application.routes.url_helpers.rails_blob_url(
      attachment, host: ENV['API_HOST'] || 'http://localhost:3000'
    )
    content_type = attachment.content_type.to_s
    type = case content_type
    when /\Aimage\// then 'image'
    when /\Avideo\// then 'video'
    when /\Aaudio\// then 'audio'
    else 'file'
    end
    { type: type, payload: { url: url } }
  end

  def post_to_graph(body)
    uri = URI.parse("https://graph.instagram.com/#{GRAPH_API_VERSION}/#{@ig_user_id}/messages")
    request = Net::HTTP::Post.new(uri)
    request.content_type = 'application/json'
    request['Authorization'] = "Bearer #{@access_token}"
    request.body = JSON.dump(body)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
      http.request(request)
    end
  end
end
