class ChargesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_billing_access!
  before_action :set_contact

  # POST /contacts/:contact_id/charges
  def create
    account = current_user.account
    api_key = account.asaas_api_key

    if api_key.blank?
      return render json: {
        error: 'asaas_not_configured',
        message: 'API Key do Asaas não configurada. Acesse Configurações → Cobrança (Asaas).'
      }, status: :unprocessable_entity
    end

    if @contact.cpf.blank?
      return render json: {
        error: 'cpf_missing',
        message: 'O contato não tem CPF/CNPJ cadastrado. Por favor, preencha antes de gerar a cobrança.'
      }, status: :unprocessable_entity
    end

    billing_type = params[:billing_type].to_s.upcase
    value        = params[:value].to_f
    due_date     = params[:due_date].presence || 3.days.from_now.strftime('%Y-%m-%d')
    description  = params[:description].presence || 'Cobrança gerada pelo CRM'

    unless %w[BOLETO PIX].include?(billing_type)
      return render json: { error: 'Tipo de cobrança inválido. Use BOLETO ou PIX.' }, status: :unprocessable_entity
    end

    if value <= 0
      return render json: { error: 'Valor deve ser maior que zero.' }, status: :unprocessable_entity
    end

    asaas = AsaasService.new(api_key, sandbox: account.asaas_sandbox?)

    customer_id = asaas.find_or_create_customer(@contact)
    charge      = asaas.create_charge(
      customer_id:  customer_id,
      billing_type: billing_type,
      value:        value,
      due_date:     due_date,
      description:  description
    )

    if charge['errors'].present?
      msg = charge['errors'].map { |e| e['description'] }.join(', ')
      return render json: { error: msg }, status: :unprocessable_entity
    end

    charge_id  = charge['id']
    valor_fmt  = "R$ #{sprintf('%.2f', value).gsub('.', ',')}"
    venc_fmt   = Date.parse(due_date).strftime('%d/%m/%Y') rescue due_date

    send_via_whatsapp(asaas, charge_id, charge['bankSlipUrl'], billing_type, description, valor_fmt, venc_fmt)

    render json: {
      charge_id:    charge_id,
      status:       charge['status'],
      value:        value,
      billing_type: billing_type,
      due_date:     due_date,
      invoice_url:  charge['invoiceUrl'],
      message:      'Cobrança gerada e enviada pelo WhatsApp!'
    }, status: :created
  rescue => e
    Rails.logger.error("ChargesController#create: #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def set_contact
    @contact = current_user.account.contacts.find(params[:contact_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Contato não encontrado.' }, status: :not_found
  end

  def require_billing_access!
    dept = current_user.department.presence || 'corretor'
    return if owner? || dept != 'corretor'
    render json: { error: 'forbidden', message: 'Corretores não podem gerar cobranças.' }, status: :forbidden
  end

  def send_via_whatsapp(asaas, charge_id, bank_slip_url, billing_type, description, valor_fmt, venc_fmt)
    conversation = @contact.conversations.order(updated_at: :desc).first
    return unless conversation

    inbox   = conversation.inbox
    baileys = WhatsappBaileysService.new(inbox)
    return unless baileys.connected?

    jid = @contact.jid.presence || baileys.resolve_jid(@contact.phone.to_s)
    return unless jid

    if billing_type == 'BOLETO'
      pdf = asaas.download_boleto_pdf(bank_slip_url)
      if pdf
        caption = "📄 *Boleto bancário*\n📝 #{description}\n💰 *#{valor_fmt}*\n📅 Vencimento: #{venc_fmt}"
        baileys.send_raw_document(jid,
          filename: "boleto_#{charge_id}.pdf",
          mimetype: 'application/pdf',
          data:     pdf,
          caption:  caption
        )
      end

    elsif billing_type == 'PIX'
      pix = asaas.get_pix_qr_code(charge_id)
      return unless pix

      caption = "📱 *PIX*\n📝 #{description}\n💰 *#{valor_fmt}*\n📅 Vencimento: #{venc_fmt}"

      if pix['encodedImage'].present?
        image_data = Base64.decode64(pix['encodedImage'])
        baileys.send_raw_image(jid, data: image_data, caption: caption)
      end

      if pix['payload'].present?
        baileys.send_message(jid, "📋 *Copia e Cola PIX:*\n```#{pix['payload']}```")
      end
    end
  rescue => e
    Rails.logger.error("ChargesController#send_via_whatsapp: #{e.message}")
  end
end
