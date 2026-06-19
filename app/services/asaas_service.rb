require 'net/http'
require 'uri'
require 'json'
require 'base64'

class AsaasService
  PRODUCTION_URL = 'https://api.asaas.com/v3'
  SANDBOX_URL    = 'https://api-sandbox.asaas.com/v3'

  def initialize(api_key, sandbox: false)
    @api_key  = api_key
    @base_url = sandbox ? SANDBOX_URL : PRODUCTION_URL
  end

  # Returns asaas customer_id, caching it on the contact to avoid duplicate lookups.
  def find_or_create_customer(contact)
    return contact.asaas_customer_id if contact.asaas_customer_id.present?

    cpf_cnpj = contact.cpf.to_s.gsub(/\D/, '')
    result   = get("/customers?cpfCnpj=#{cpf_cnpj}&limit=1")
    existing = result.dig('data', 0)

    customer_id = if existing
      existing['id']
    else
      name = contact.name.presence ||
             "#{contact.first_name} #{contact.last_name}".strip.presence ||
             'Cliente'

      created = post('/customers', {
        name:     name,
        cpfCnpj: cpf_cnpj,
        email:   contact.email.presence,
        phone:   contact.phone&.gsub(/\D/, '')
      }.compact)

      raise "Asaas: #{created.dig('errors', 0, 'description')}" if created['errors'].present?
      created['id']
    end

    contact.update_column(:asaas_customer_id, customer_id)
    customer_id
  end

  def create_charge(customer_id:, billing_type:, value:, due_date:, description:)
    post('/payments', {
      customer:    customer_id,
      billingType: billing_type,
      value:       value.to_f.round(2),
      dueDate:     due_date,
      description: description
    })
  end

  # Downloads the boleto PDF from the public bankSlipUrl returned by the payment creation.
  # url is the full URL, e.g. "https://www.asaas.com/b/pdf/XXXXXXXX"
  def download_boleto_pdf(url)
    return nil if url.blank?

    uri     = URI.parse(url)
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'CRM-Imobiliario/1.0'

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
                               open_timeout: 15, read_timeout: 30) { |h| h.request(request) }

    return response.body if response.is_a?(Net::HTTPSuccess)
    Rails.logger.error("Asaas boleto PDF #{response.code}: #{url}")
    nil
  rescue => e
    Rails.logger.error("Asaas download_boleto_pdf: #{e.message}")
    nil
  end

  # Returns { 'encodedImage' => base64_png, 'payload' => 'copia-e-cola' }
  def get_pix_qr_code(charge_id)
    get("/payments/#{charge_id}/pixQrCode")
  rescue => e
    Rails.logger.error("Asaas get_pix_qr_code: #{e.message}")
    nil
  end

  # Returns { ok: true, name: '...' } or { ok: false, error: '...' }
  def test_connection
    result = get('/myAccount/commercialInfo')
    name = result['companyName'].presence || result['tradingName'].presence || result['name'].presence
    name.present? ? { ok: true, name: name } : { ok: false, error: 'Resposta inválida' }
  rescue => e
    { ok: false, error: e.message }
  end

  private

  def get(path)
    uri = URI.parse("#{@base_url}#{path}")
    req = Net::HTTP::Get.new(uri)
    req['access_token']  = @api_key
    req['Content-Type']  = 'application/json'
    req['User-Agent']    = 'CRM-Imobiliario/1.0'

    resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                           open_timeout: 10, read_timeout: 20) { |h| h.request(req) }
    JSON.parse(resp.body)
  rescue => e
    Rails.logger.error("AsaasService GET #{path}: #{e.message}")
    {}
  end

  def post(path, body)
    uri = URI.parse("#{@base_url}#{path}")
    req = Net::HTTP::Post.new(uri)
    req['access_token']  = @api_key
    req['Content-Type']  = 'application/json'
    req['User-Agent']    = 'CRM-Imobiliario/1.0'
    req.body = body.to_json

    resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                           open_timeout: 10, read_timeout: 20) { |h| h.request(req) }
    JSON.parse(resp.body)
  rescue => e
    Rails.logger.error("AsaasService POST #{path}: #{e.message}")
    { 'errors' => [{ 'description' => e.message }] }
  end
end
