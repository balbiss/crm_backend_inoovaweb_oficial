class DashboardController < ApplicationController
  def index
    is_owner = current_user.empresa? || current_user.admin? || current_user.has_permission?('view_all_contacts')
    scope = is_owner ? current_user.account.contacts : current_user.account.contacts.where(user_id: current_user.id)

    active_customers  = scope.count
    pretensao_venda   = scope.where(intention: ['venda', 'Venda', 'VENDA']).count
    quente_count      = scope.where(temperature: ['quente', 'Quente', 'QUENTE']).count
    morno_count       = scope.where(temperature: ['morno', 'Morno', 'MORNO']).count
    frio_count        = scope.where(temperature: ['frio', 'Frio', 'FRIO']).count
    leads_by_source   = scope.where.not(source: [nil, '']).group(:source).count

    render json: {
      is_owner: is_owner,
      kpis: {
        active_customers: active_customers,
        pretensao_venda:  pretensao_venda,
        temperature: {
          quente: quente_count,
          morno:  morno_count,
          frio:   frio_count
        }
      },
      leads_by_source: leads_by_source
    }
  end
end
