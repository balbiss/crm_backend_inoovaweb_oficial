require 'openai'

class PropertyMatchJob < ApplicationJob
  queue_as :default

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property

    account = property.account
    api_key = GlobalSetting.fetch('openai_api_key').presence || ENV['OPENAI_API_KEY']
    return unless api_key

    client = OpenAI::Client.new(access_token: api_key)
    property_desc = build_property_description(property)

    leads = account.contacts
      .where.not(intention: [nil, ''])
      .where.not(status: 'won')
      .includes(conversations: :inbox)
      .limit(100)

    matched = []

    leads.each do |lead|
      response = client.chat(
        parameters: {
          model: 'gpt-4o-mini',
          messages: [
            { role: 'system', content: 'Você é um assistente de match imobiliário. Responda APENAS "SIM" ou "NÃO".' },
            { role: 'user', content: "Imóvel: #{property_desc}\n\nIntenção do lead: #{lead.intention}\n\nEste imóvel atende a intenção do lead?" }
          ],
          temperature: 0.1,
          max_tokens: 5
        }
      )
      answer = response.dig('choices', 0, 'message', 'content').to_s.strip.upcase
      matched << lead if answer.start_with?('SIM')
    rescue => e
      Rails.logger.error("PropertyMatchJob lead #{lead.id}: #{e.message}")
    end

    return if matched.empty?

    ActionCable.server.broadcast("conversations_channel_#{account.id}", {
      event: 'property_match_found',
      property_id: property.id,
      property_title: property.title.presence || property.property_type || 'Novo imóvel',
      match_count: matched.count
    })

    matched.each do |lead|
      conversation = lead.conversations.find { |c| c.inbox.present? }
      next unless conversation

      baileys = WhatsappBaileysService.new(conversation.inbox)
      jid = lead.jid.presence || lead.phone
      next unless jid

      msg = build_match_message(property, lead)
      baileys_id = baileys.send_message(jid, msg)

      Message.create!(
        account: account,
        conversation: conversation,
        text: msg,
        sender_type: 'User',
        sender_id: nil,
        source_id: baileys_id.presence || "match_#{SecureRandom.hex(8)}",
        status: :delivered
      )
      conversation.update_column(:last_activity_at, Time.current)
    rescue => e
      Rails.logger.error("PropertyMatchJob send to lead #{lead.id}: #{e.message}")
    end
  end

  private

  def build_property_description(p)
    [
      ("Tipo: #{p.property_type}" if p.property_type.present?),
      ("Transação: #{p.listing_type}" if p.listing_type.present?),
      ("Bairro: #{p.neighborhood}, #{p.city}" if p.neighborhood.present?),
      ("Quartos: #{p.bedrooms}" if p.bedrooms.present?),
      ("Área: #{p.built_area || p.total_area}m²" if (p.built_area || p.total_area).present?),
      ("Preço: R$ #{p.price}" if p.price.present?)
    ].compact.join('. ')
  end

  def build_match_message(property, lead)
    name   = lead.name.presence || lead.first_name.presence || 'Olá'
    tipo   = property.property_type || 'Imóvel'
    bairro = property.neighborhood.present? ? " em #{property.neighborhood}" : ''
    qtos   = property.bedrooms.present? ? ", #{property.bedrooms} quartos" : ''
    preco  = property.price.present? ? " por R$ #{ActionController::Base.helpers.number_with_delimiter(property.price.to_i, delimiter: '.')}" : ''
    "#{name}! 🏠 Temos um novo #{tipo}#{bairro}#{qtos}#{preco} que pode ser exatamente o que você procura! Posso te contar mais detalhes?"
  end
end
