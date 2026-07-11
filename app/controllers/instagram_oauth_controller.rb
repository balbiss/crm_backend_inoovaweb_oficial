require 'net/http'
require 'uri'
require 'json'

class InstagramOauthController < ApplicationController
  GRAPH_API_VERSION = 'v21.0'.freeze
  SCOPES = 'instagram_basic,instagram_manage_messages,pages_show_list,pages_manage_metadata'.freeze

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
    url = "https://www.facebook.com/#{GRAPH_API_VERSION}/dialog/oauth?#{params.to_query}"
    render json: { url: url }
  end

  # Chamado pela Meta redirecionando o navegador do usuário — não passa pelo
  # JWT do frontend, por isso não usa authenticate_user!/current_user.
  def callback
    data = verifier.verify(params[:state])
    account_id = data['account_id']

    short_lived_token = exchange_code_for_token(params[:code])
    long_lived_token, expires_in = exchange_for_long_lived_token(short_lived_token)

    page = find_page_with_instagram_account(long_lived_token)
    raise 'Nenhuma Página com conta Instagram Business vinculada foi encontrada.' unless page

    inbox = Inbox.find_or_initialize_by(account_id: account_id, provider: 'instagram', instagram_page_id: page[:page_id])
    inbox.name = "Instagram - #{page[:username]}".presence || 'Instagram'
    inbox.instagram_business_account_id = page[:ig_user_id]
    inbox.instagram_access_token = page[:page_access_token]
    inbox.instagram_token_expires_at = expires_in.present? ? Time.current + expires_in.to_i.seconds : nil
    inbox.instagram_username = page[:username]
    inbox.save!

    redirect_to "#{ENV.fetch('FRONTEND_URL')}/settings/inboxes/new?instagram_inbox_id=#{inbox.id}"
  rescue ActiveSupport::MessageVerifier::InvalidSignature, StandardError => e
    Rails.logger.error("Instagram OAuth callback error: #{e.message}")
    redirect_to "#{ENV.fetch('FRONTEND_URL')}/settings/inboxes/new?instagram_error=#{CGI.escape(e.message)}"
  end

  private

  def verifier
    Rails.application.message_verifier(:instagram_oauth)
  end

  def callback_url
    "#{ENV.fetch('API_HOST', 'http://localhost:3000')}/instagram_oauth/callback"
  end

  def exchange_code_for_token(code)
    uri = URI.parse("https://graph.facebook.com/#{GRAPH_API_VERSION}/oauth/access_token")
    uri.query = URI.encode_www_form({
      client_id: ENV.fetch('INSTAGRAM_APP_ID'),
      client_secret: ENV.fetch('INSTAGRAM_APP_SECRET'),
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
      client_id: ENV.fetch('INSTAGRAM_APP_ID'),
      client_secret: ENV.fetch('INSTAGRAM_APP_SECRET'),
      fb_exchange_token: short_lived_token
    })
    response = Net::HTTP.get_response(uri)
    raise "Falha ao trocar por token de longa duração: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(response.body)
    [parsed['access_token'], parsed['expires_in']]
  end

  def find_page_with_instagram_account(user_token)
    uri = URI.parse("https://graph.facebook.com/#{GRAPH_API_VERSION}/me/accounts")
    uri.query = URI.encode_www_form({ access_token: user_token })
    response = Net::HTTP.get_response(uri)
    raise "Falha ao listar Páginas: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    pages = JSON.parse(response.body)['data'] || []
    pages.each do |page|
      page_id = page['id']
      page_access_token = page['access_token']

      details_uri = URI.parse("https://graph.facebook.com/#{GRAPH_API_VERSION}/#{page_id}")
      details_uri.query = URI.encode_www_form({ fields: 'instagram_business_account', access_token: page_access_token })
      details_response = Net::HTTP.get_response(details_uri)
      next unless details_response.is_a?(Net::HTTPSuccess)

      details = JSON.parse(details_response.body)
      ig_account = details['instagram_business_account']
      next unless ig_account

      ig_user_id = ig_account['id']
      username = fetch_instagram_username(ig_user_id, page_access_token)

      return { page_id: page_id, page_access_token: page_access_token, ig_user_id: ig_user_id, username: username }
    end
    nil
  end

  def fetch_instagram_username(ig_user_id, access_token)
    uri = URI.parse("https://graph.facebook.com/#{GRAPH_API_VERSION}/#{ig_user_id}")
    uri.query = URI.encode_www_form({ fields: 'username', access_token: access_token })
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)['username']
  rescue StandardError
    nil
  end
end
