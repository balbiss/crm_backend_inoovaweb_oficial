class Admin::DashboardController < Admin::BaseController
  def index
    # Métricas globais do SaaS
    total_accounts = Account.count
    active_accounts = Account.where(subscription_status: 'active').count
    trialing_accounts = Account.where(subscription_status: 'trialing').count

    # Calcular o MRR estimado baseado no Stripe, ou mock para desenvolvimento
    mrr = active_accounts * 197.00 # Exemplo de R$197 por assinatura

    render json: {
      metrics: {
        total_accounts: total_accounts,
        active_accounts: active_accounts,
        trialing_accounts: trialing_accounts,
        estimated_mrr: mrr
      }
    }
  end
end
