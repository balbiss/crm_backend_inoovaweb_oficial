require_relative '../services/whatsapp_baileys_service'

class InboxesController < ApplicationController
  before_action :set_inbox, only: %i[ show update destroy qr_code status ]

  def index
    @inboxes = Inbox.all
    render json: @inboxes
  end

  def show
    render json: @inbox
  end

  def create
    @inbox = Inbox.new(inbox_params)

    if @inbox.save
      if @inbox.provider == 'baileys'
        # Assume our app is running on localhost:3000 for webhooks locally
        webhook_url = "http://web:3000/webhooks/baileys"
        service = WhatsappBaileysService.new(@inbox)
        # Attempt to create the connection in the external Baileys API
        service.create_connection(webhook_url) rescue StandardError
      end
      
      render json: @inbox, status: :created
    else
      render json: @inbox.errors, status: :unprocessable_entity
    end
  end

  def update
    if @inbox.update(inbox_params)
      render json: @inbox
    else
      render json: @inbox.errors, status: :unprocessable_entity
    end
  end

  def qr_code
    baileys = WhatsappBaileysService.new(@inbox)
    qr = baileys.fetch_qr_code
    
    if qr.nil?
      status = Rails.cache.read("inbox:#{@inbox.id}:status")
      unless %w[connecting open].include?(status)
        baileys.delete_connection rescue nil
        sleep 0.5
        webhook_url = "http://web:3000/webhooks/baileys"
        baileys.create_connection(webhook_url) rescue nil
        sleep 2.0
        qr = baileys.fetch_qr_code
      end
    end

    if qr
      render json: { qr_code: qr }
    else
      render json: { qr_code: nil, message: 'QR Code não disponível. Tente novamente em instantes.' }
    end
  end

  def status
    baileys = WhatsappBaileysService.new(@inbox)
    connected = baileys.connected?
    render json: { connected: connected }
  end

  def destroy
    begin
      WhatsappBaileysService.new(@inbox).delete_connection
    rescue StandardError => e
      Rails.logger.error("Failed to delete connection in Baileys: #{e.message}")
    end
    @inbox.destroy!
    head :no_content
  end

  private
    def set_inbox
      @inbox = Inbox.find(params.expect(:id))
    end

    def inbox_params
      params.expect(inbox: [ :name, :provider, :api_url, :api_key, :phone_number ])
    end
end
