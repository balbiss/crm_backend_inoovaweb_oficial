class DashboardController < ApplicationController
  def index
    # Total Active Contacts (assuming all non-deleted are active for now)
    active_customers = Contact.count
    
    # Intention Venda Count
    pretensao_venda = Contact.where(intention: ['venda', 'Venda', 'VENDA']).count
    
    # Temperature Counts
    quente_count = Contact.where(temperature: ['quente', 'Quente', 'QUENTE']).count
    morno_count = Contact.where(temperature: ['morno', 'Morno', 'MORNO']).count
    frio_count = Contact.where(temperature: ['frio', 'Frio', 'FRIO']).count
    
    # Leads by Source
    # Count how many contacts per source, excluding nil/blank sources
    leads_by_source = Contact.where.not(source: [nil, '']).group(:source).count
    
    render json: {
      kpis: {
        active_customers: active_customers,
        pretensao_venda: pretensao_venda,
        temperature: {
          quente: quente_count,
          morno: morno_count,
          frio: frio_count
        }
      },
      leads_by_source: leads_by_source
    }
  end
end
