class CustomDeviseMailer < Devise::Mailer
  def reset_password_instructions(record, token, opts = {})
    @frontend_reset_url = "#{ENV.fetch('FRONTEND_URL', 'https://crmchat.visitaia.com.br')}/reset-password?reset_password_token=#{token}"
    super
  end
end
