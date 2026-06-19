class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('SMTP_USER', 'suporte@visitaia.com.br')
  layout "mailer"
end
