class AddAiListingScopeToInboxes < ActiveRecord::Migration[8.1]
  def change
    # 'all' = a IA do canal enxerga todos os imóveis/condomínios da conta
    # (comportamento antigo); 'selected' = só os condomínios marcados em
    # ai_condominium_ids (+ imóveis avulsos se ai_include_properties).
    add_column :inboxes, :ai_listing_scope, :string, default: 'all', null: false
    add_column :inboxes, :ai_condominium_ids, :integer, array: true, default: [], null: false
    add_column :inboxes, :ai_include_properties, :boolean, default: true, null: false
  end
end
