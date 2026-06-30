module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = request.params[:token]
      return reject_unauthorized_connection unless token

      begin
        secret = Rails.application.credentials.secret_key_base ||
                 'fallback_secret_for_development_do_not_use_in_prod'
        payload = JWT.decode(token, secret, true, algorithms: ['HS256']).first
        user = User.find(payload['sub'])
        user.active_for_authentication? ? user : reject_unauthorized_connection
      rescue
        reject_unauthorized_connection
      end
    end
  end
end
