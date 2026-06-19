class WelcomeMailer < ApplicationMailer
  DEPT_LABELS = {
    'corretor'   => 'Corretor(a)',
    'suporte'    => 'Suporte',
    'financeiro' => 'Financeiro',
    'manutencao' => 'Manutenção'
  }.freeze

  def welcome(user, plain_password)
    @user           = user
    @plain_password = plain_password
    @dept_label     = DEPT_LABELS[user.department] || 'Corretor(a)'
    @login_url      = "#{ENV.fetch('FRONTEND_URL', 'https://crmchat.visitaia.com.br')}/login"
    @app_name       = ENV.fetch('APP_NAME', 'VisitaIA CRM')

    mail(
      to:      user.email,
      subject: "Bem-vindo(a) ao #{@app_name}! Seus dados de acesso"
    )
  end
end
