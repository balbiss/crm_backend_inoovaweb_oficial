require 'net/http'
require 'uri'
require 'json'

# Conecta a Página do Facebook usada nas campanhas de "Geração de Cadastros"
# (Lead Ads) à conta, via "Login do Facebook para Empresas" — produto
# diferente do usado pelo Instagram (que usa login direto). Lead Ads exige
# uma Página vinculada à campanha, não tem como fugir disso.
class FacebookLeadsOauthController < ApplicationController
  GRAPH_API_VERSION = 'v21.0'.freeze
  SCOPES = 'leads_retrieval,pages_show_list,pages_manage_metadata'.freeze

  before_action :authenticate_user!, only: [:authorize_url, :disconnect]
  before_action :require_owner!, only: [:authorize_url, :disconnect]

  def authorize_url
    state = verifier.generate({ account_id: current_user.account_id, ts: Time.current.to_i }, expires_in: 10.minutes)

    params = {
      client_id: ENV.fetch('FACEBOOK_APP_ID'),
      redirect_uri: callback_url,
      scope: SCOPES,
      response_type: 'code',
      state: state
    }
    url = "https://www.facebook.com/#{GRAPH_API_VERSION}/dialog/oauth?#{params.to_query}"
    render json: { url: url }
  end

  # Chamado pela Meta redirecionando o navegador do usuário — não passa pelo
  # JWT do frontend, por isso não usa authenticate_user!/current_user.
  def callback
    data = verifier.verify(params[:state])
    account_id = data['account_id']

    user_token = exchange_code_for_token(params[:code])
    long_lived_token = exchange_for_long_lived_token(user_token)
    page = find_leads_page(long_lived_token)
    raise 'Nenhuma Página com acesso a Lead Ads foi encontrada nesta conta do Facebook.' unless page

    account = Account.find(account_id)
    account.update!(
      facebook_page_id: page[:id],
      facebook_page_access_token: page[:access_token],
      facebook_page_name: page[:name],
      facebook_token_expires_at: nil
    )

    redirect_to "#{ENV.fetch('FRONTEND_URL')}/settings/account?facebook_leads_connected=1", allow_other_host: true
  rescue ActiveSupport::MessageVerifier::InvalidSignature, StandardError => e
    Rails.logger.error("Facebook Leads OAuth callback error: #{e.message}")
    redirect_to "#{ENV.fetch('FRONTEND_URL')}/settings/account?facebook_leads_error=#{CGI.escape(e.message)}", allow_other_host: true
  end

  def disconnect
    current_user.account.update!(
      facebook_page_id: nil, facebook_page_access_token: nil,
      facebook_page_name: nil, facebook_token_expires_at: nil
    )
    render json: { success: true }
  end

  private

  def verifier
    Rails.application.message_verifier(:facebook_leads_oauth)
  end

  def callback_url
    "#{ENV.fetch('API_HOST', 'http://localhost:3000')}/facebook_leads_oauth/callback"
  end

  def exchange_code_for_token(code)
    uri = URI.parse("https://graph.facebook.com/#{GRAPH_API_VERSION}/oauth/access_token")
    uri.query = URI.encode_www_form({
      client_id: ENV.fetch('FACEBOOK_APP_ID'),
      client_secret: ENV.fetch('FACEBOOK_APP_SECRET'),
      redirect_uri: callback_url,
      code: code
    })
    response = Net::HTTP.get_response(uri)
    raise "Falha ao trocar code por token: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)['access_token']
  end

  def exchange_for_long_lived_token(short_lived_token)
    uri = URI.parse("https://graph.facebook.com/#{GRAPH_API_VERSION}/oauth/access_token")
    uri.query = URI.encode_www_form({
      grant_type: 'fb_exchange_token',
      client_id: ENV.fetch('FACEBOOK_APP_ID'),
      client_secret: ENV.fetch('FACEBOOK_APP_SECRET'),
      fb_exchange_token: short_lived_token
    })
    response = Net::HTTP.get_response(uri)
    raise "Falha ao trocar por token de longa duração: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)['access_token']
  end

  # Retorna a primeira Página com acesso concedido (o Page Access Token de
  # cada Página já vem nesta mesma chamada — não precisa de request extra).
  def find_leads_page(user_token)
    uri = URI.parse("https://graph.facebook.com/#{GRAPH_API_VERSION}/me/accounts")
    uri.query = URI.encode_www_form({ access_token: user_token })
    response = Net::HTTP.get_response(uri)
    raise "Falha ao listar Páginas: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    pages = JSON.parse(response.body)['data'] || []
    page = pages.first
    return nil unless page

    { id: page['id'], access_token: page['access_token'], name: page['name'] }
  end
end
