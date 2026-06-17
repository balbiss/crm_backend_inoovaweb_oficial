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

  def send_message(recipient_phone, text, attachment = nil)
    # The recipient_phone must be in format like 5511999999999@s.whatsapp.net
    # If it's just a number, we append the domain
    jid = recipient_phone
    unless jid.include?('@')
      jid = "#{jid.delete('+')}@s.whatsapp.net"
    end

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
    jid = recipient_phone
    unless jid.include?('@')
      jid = "#{jid.delete('+')}@s.whatsapp.net"
    end

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
end
