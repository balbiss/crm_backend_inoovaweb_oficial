require 'net/http'
require 'uri'
require 'json'
require 'cgi'

class WhatsappBaileysService
  def initialize(inbox)
    @inbox = inbox
    @api_url = inbox.api_url.presence || ENV['BAILEYS_API_URL'].presence || 'http://baileys-api:3025'
    @api_key = inbox.api_key.presence || ENV['BAILEYS_API_KEY'].presence || 'innovaweb2025'
    
    phone = inbox.phone_number.to_s.gsub(/[^\d+]/, '')
    phone = "+#{phone}" unless phone.start_with?('+')
    @phone_number = phone
  end

  def create_connection(webhook_url)
    # Limpa cache antigo para nova conexão
    Rails.cache.delete("inbox:#{@inbox.id}:qr_code")
    Rails.cache.delete("inbox:#{@inbox.id}:status")

    # Garante que o telefone esteja presente no webhookUrl
    uri_webhook = URI.parse(webhook_url)
    query = URI.decode_www_form(uri_webhook.query || '')
    query.reject! { |k, _| k == 'phone' }
    query << ['phone', @phone_number]
    uri_webhook.query = URI.encode_www_form(query)
    final_webhook_url = uri_webhook.to_s

    uri = URI.parse("#{@api_url}/connections/#{@phone_number}")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request["x-api-key"] = @api_key
    
    request.body = JSON.dump({
      "webhookUrl" => final_webhook_url,
      "webhookVerifyToken" => "innovaweb-token"
    })

    req_options = {
      use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    response.is_a?(Net::HTTPSuccess)
  end

  def resolve_jid(phone)
    digits = phone.gsub(/\D/, '')
    digits = "55#{digits}" unless digits.start_with?('55')

    # Testa os dois formatos brasileiros simultaneamente (problema do nono dígito)
    # Ex: 5511912345678 (com 9) e 551112345678 (sem 9)
    candidates = [digits]
    if digits.start_with?('55') && digits.length == 13
      candidates << digits[0..3] + digits[5..]   # remove o 9: 5511912345678 → 551112345678
    elsif digits.start_with?('55') && digits.length == 12
      candidates << digits[0..3] + '9' + digits[4..]  # adiciona o 9: 551112345678 → 5511912345678
    end

    jids = candidates.map { |d| "#{d}@s.whatsapp.net" }

    uri = URI.parse("#{@api_url}/connections/#{@phone_number}/on-whatsapp")
    request = Net::HTTP::Post.new(uri)
    request.content_type = 'application/json'
    request['x-api-key'] = @api_key
    request.body = JSON.dump({ 'jids' => jids })

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
                                open_timeout: 5, read_timeout: 10) { |h| h.request(request) }
    results = JSON.parse(response.body) rescue []
    found = results.find { |r| r.is_a?(Hash) && r['exists'] }
    found&.dig('jid')
  rescue => e
    Rails.logger.error("resolve_jid error: #{e.message}")
    nil
  end

  def send_message(recipient_phone, text, attachment = nil)
    # The recipient_phone must be in format like 5511999999999@s.whatsapp.net
    # If it's just a number, we append the domain
    jid = normalize_jid(recipient_phone)

    uri = URI.parse("#{@api_url}/connections/#{@phone_number}/send-message")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request["x-api-key"] = @api_key
    
    payload = {
      "jid" => jid,
      "messageContent" => {}
    }

    if attachment.present?
      content_type = attachment.content_type
      base64_data = Base64.strict_encode64(attachment.download)

      if content_type.start_with?('image/')
        payload["messageContent"]["image"] = base64_data
        payload["messageContent"]["caption"] = text if text.present?
      elsif content_type.start_with?('audio/') || content_type.start_with?('video/')
        media_key = content_type.start_with?('audio/') ? "audio" : "video"
        payload["messageContent"][media_key] = base64_data
        payload["messageContent"]["mimetype"] = content_type
        payload["messageContent"]["ptt"] = true if media_key == "audio"
        payload["messageContent"]["caption"] = text if text.present? && media_key == "video"
      else
        payload["messageContent"]["document"] = base64_data
        payload["messageContent"]["mimetype"] = content_type
        payload["messageContent"]["fileName"] = attachment.filename.to_s
        payload["messageContent"]["caption"] = text if text.present?
      end
    else
      payload["messageContent"]["text"] = text
    end

    request.body = JSON.dump(payload)

    req_options = {
      use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    Rails.logger.info("Baileys send_message response code: #{response.code}, body: #{response.body}")
    puts "Baileys API Response: #{response.body}" # Imprime no console também para o rails runner
    if response.is_a?(Net::HTTPSuccess)
      parsed = JSON.parse(response.body) rescue {}
      parsed.dig("data", "key", "id")
    end
  end

  def send_presence_update(recipient_phone, presence = 'composing')
    jid = normalize_jid(recipient_phone)

    uri = URI.parse("#{@api_url}/connections/#{@phone_number}/presence")
    request = Net::HTTP::Patch.new(uri)
    request.content_type = "application/json"
    request["x-api-key"] = @api_key

    payload = { "type" => presence, "toJid" => jid }
    request.body = JSON.dump(payload)

    req_options = {
      use_ssl: uri.scheme == "https",
      open_timeout: 5,
      read_timeout: 10
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    response.is_a?(Net::HTTPSuccess)
  rescue StandardError => e
    Rails.logger.error("Baileys send_presence_update error: #{e.message}")
    false
  end

  def fetch_profile_picture_url(jid)
    uri = URI.parse("#{@api_url}/connections/#{@phone_number}/profile-picture-url?jid=#{CGI.escape(jid)}")
    request = Net::HTTP::Get.new(uri)
    request["x-api-key"] = @api_key
    
    req_options = {
      use_ssl: uri.scheme == "https",
      open_timeout: 5,
      read_timeout: 10
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      return data.dig('data', 'profilePictureUrl')
    end
    nil
  rescue => e
    Rails.logger.error("Baileys fetch_profile_picture_url error: #{e.message}")
    nil
  end

  def fetch_qr_code
    Rails.cache.read("inbox:#{@inbox.id}:qr_code")
  end

  def connected?
    # Cache tem prioridade (escrito pelo webhook connection.update)
    cached = Rails.cache.read("inbox:#{@inbox.id}:status")
    return cached == 'open' unless cached.nil?

    # Cache vazio (ex: após restart) — consulta o Baileys API diretamente
    begin
      uri = URI.parse("#{@api_url}/connections/#{@phone_number}/presence")
      req = Net::HTTP::Patch.new(uri)
      req.content_type = "application/json"
      req["x-api-key"] = @api_key
      req.body = JSON.dump({ "type" => "available" })
      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 5) { |h| h.request(req) }
      is_connected = res.is_a?(Net::HTTPSuccess)
      Rails.cache.write("inbox:#{@inbox.id}:status", is_connected ? 'open' : 'close', expires_in: 2.minutes)
      is_connected
    rescue StandardError
      false
    end
  end

  # Sends raw binary data as a document (e.g. boleto PDF from Asaas)
  def send_raw_document(jid, filename:, mimetype:, data:, caption: nil)
    jid = normalize_jid(jid)

    uri = URI.parse("#{@api_url}/connections/#{@phone_number}/send-message")
    req = Net::HTTP::Post.new(uri)
    req.content_type = 'application/json'
    req['x-api-key'] = @api_key

    content = {
      'document' => Base64.strict_encode64(data),
      'mimetype' => mimetype,
      'fileName' => filename
    }
    content['caption'] = caption if caption.present?

    req.body = JSON.dump({ 'jid' => jid, 'messageContent' => content })
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
                               open_timeout: 20, read_timeout: 40) { |h| h.request(req) }
    response.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.error("Baileys send_raw_document error: #{e.message}")
    false
  end

  # Sends raw binary data as an image (e.g. PIX QR code from Asaas)
  def send_raw_image(jid, data:, caption: nil)
    jid = normalize_jid(jid)

    uri = URI.parse("#{@api_url}/connections/#{@phone_number}/send-message")
    req = Net::HTTP::Post.new(uri)
    req.content_type = 'application/json'
    req['x-api-key'] = @api_key

    content = { 'image' => Base64.strict_encode64(data) }
    content['caption'] = caption if caption.present?

    req.body = JSON.dump({ 'jid' => jid, 'messageContent' => content })
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
                               open_timeout: 20, read_timeout: 40) { |h| h.request(req) }
    response.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.error("Baileys send_raw_image error: #{e.message}")
    false
  end

  def delete_connection
    Rails.cache.delete("inbox:#{@inbox.id}:qr_code")
    Rails.cache.delete("inbox:#{@inbox.id}:status")

    uri = URI.parse("#{@api_url}/connections/#{@phone_number}")
    request = Net::HTTP::Delete.new(uri)
    request["x-api-key"] = @api_key
    
    req_options = { use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10 }
    
    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end
    
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError => e
    Rails.logger.error("Baileys delete_connection error: #{e.message}")
    false
  end

  private

  # Aceita um JID pronto (com '@') ou um telefone em qualquer formatação
  # (com parenteses, espacos, hifens etc) e devolve sempre um JID valido,
  # prefixando o DDI 55 quando ausente.
  def normalize_jid(phone_or_jid)
    return phone_or_jid if phone_or_jid.include?('@')

    digits = phone_or_jid.gsub(/\D/, '')
    digits = "55#{digits}" unless digits.start_with?('55')
    "#{digits}@s.whatsapp.net"
  end
end
