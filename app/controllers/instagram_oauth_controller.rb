require 'net/http'
require 'uri'
require 'json'

# Fluxo "Instagram API with Instagram Login": login direto com a conta do
# Instagram (Business/Creator), sem precisar de uma Página do Facebook
# vinculada. Diferente do "Instagram API with Facebook Login", que usa
# graph.facebook.com e permissões pages_*.
class InstagramOauthController < ApplicationController
  GRAPH_API_VERSION = 'v21.0'.freeze
  SCOPES = 'instagram_business_basic,instagram_business_manage_messages'.freeze

  before_action :authenticate_user!, only: :authorize_url
  before_action :require_owner!, only: :authorize_url

  def authorize_url
    state = verifier.generate({ account_id: current_user.account_id, ts: Time.current.to_i }, expires_in: 10.minutes)

    params = {
      client_id: ENV.fetch('INSTAGRAM_APP_ID'),
      redirect_uri: callback_url,
      scope: SCOPES,
      response_type: 'code',
      state: state
    }
    url = "https://www.instagram.com/oauth/authorize?#{params.to_query}"
    render json: { url: url }
  end

  # Chamado pela Meta redirecionando o navegador do usuário — não passa pelo
  # JWT do frontend, por isso não usa authenticate_user!/current_user.
  def callback
    data = verifier.verify(params[:state])
    account_id = data['account_id']

    short_lived_token, = exchange_code_for_token(params[:code])
    long_lived_token, expires_in = exchange_for_long_lived_token(short_lived_token)
    # O "user_id" devolvido na troca do code é o ASID (escopo app+usuário) —
    # o webhook identifica a conta pelo IGSID de verdade, então buscamos ele
    # separado via /me (mesmo campo "user_id", mas com significado diferente
    # nesse endpoint).
    ig_user_id, username = fetch_instagram_identity(long_lived_token)
    raise 'Não foi possível identificar a conta do Instagram (user_id ausente).' if ig_user_id.blank?

    inbox = Inbox.find_or_initialize_by(account_id: account_id, provider: 'instagram', instagram_business_account_id: ig_user_id)
    inbox.name = "Instagram - #{username}".presence || 'Instagram'
    inbox.instagram_page_id = ig_user_id
    inbox.instagram_access_token = long_lived_token
    inbox.instagram_token_expires_at = expires_in.present? ? Time.current + expires_in.to_i.seconds : nil
    inbox.instagram_username = username
    inbox.save!

    redirect_to "#{ENV.fetch('FRONTEND_URL')}/settings/inboxes/new?instagram_inbox_id=#{inbox.id}", allow_other_host: true
  rescue ActiveSupport::MessageVerifier::InvalidSignature, StandardError => e
    Rails.logger.error("Instagram OAuth callback error: #{e.message}")
    redirect_to "#{ENV.fetch('FRONTEND_URL')}/settings/inboxes/new?instagram_error=#{CGI.escape(e.message)}", allow_other_host: true
  end

  private

  def verifier
    Rails.application.message_verifier(:instagram_oauth)
  end

  def callback_url
    "#{ENV.fetch('API_HOST', 'http://localhost:3000')}/instagram_oauth/callback"
  end

  # Token de curta duração (~1h). O "user_id" que essa resposta traz é um
  # ASID (escopo app+usuário), não o IGSID real — por isso é descartado
  # pelo chamador e buscamos o IGSID de verdade depois via #fetch_instagram_identity.
  def exchange_code_for_token(code)
    uri = URI.parse('https://api.instagram.com/oauth/access_token')
    request = Net::HTTP::Post.new(uri)
    request.set_form_data(
      client_id: ENV.fetch('INSTAGRAM_APP_ID'),
      client_secret: ENV.fetch('INSTAGRAM_APP_SECRET'),
      grant_type: 'authorization_code',
      redirect_uri: callback_url,
      code: code
    )
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    raise "Falha ao trocar code por token: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(response.body)
    [parsed['access_token'], parsed['user_id']]
  end

  def exchange_for_long_lived_token(short_lived_token)
    uri = URI.parse('https://graph.instagram.com/access_token')
    uri.query = URI.encode_www_form({
      grant_type: 'ig_exchange_token',
      client_secret: ENV.fetch('INSTAGRAM_APP_SECRET'),
      access_token: short_lived_token
    })
    response = Net::HTTP.get_response(uri)
    raise "Falha ao trocar por token de longa duração: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(response.body)
    [parsed['access_token'], parsed['expires_in']]
  end

  # Retorna [igsid, username] usando o próprio token (rota "/me"), que é a
  # forma confiável de pegar o IGSID de verdade (o mesmo usado pelo webhook).
  def fetch_instagram_identity(access_token)
    uri = URI.parse("https://graph.instagram.com/#{GRAPH_API_VERSION}/me")
    uri.query = URI.encode_www_form({ fields: 'user_id,username', access_token: access_token })
    response = Net::HTTP.get_response(uri)
    return [nil, nil] unless response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(response.body)
    [parsed['user_id'], parsed['username']]
  rescue StandardError
    [nil, nil]
  end
end
