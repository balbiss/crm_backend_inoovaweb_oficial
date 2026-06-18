class AddMissingPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # properties — buscas frequentes da IA e filtros do frontend
    add_index :properties, [:account_id, :status],        name: 'idx_properties_account_status'       unless index_exists?(:properties, [:account_id, :status])
    add_index :properties, [:account_id, :listing_type],  name: 'idx_properties_account_listing_type' unless index_exists?(:properties, [:account_id, :listing_type])
    add_index :properties, [:account_id, :neighborhood],  name: 'idx_properties_account_neighborhood' unless index_exists?(:properties, [:account_id, :neighborhood])
    add_index :properties, [:account_id, :bedrooms],      name: 'idx_properties_account_bedrooms'     unless index_exists?(:properties, [:account_id, :bedrooms])
    add_index :properties, [:account_id, :price],         name: 'idx_properties_account_price'        unless index_exists?(:properties, [:account_id, :price])

    # contacts — dashboard KPIs e relatórios
    add_index :contacts, [:account_id, :temperature], name: 'idx_contacts_account_temperature' unless index_exists?(:contacts, [:account_id, :temperature])
    add_index :contacts, [:account_id, :source],      name: 'idx_contacts_account_source'      unless index_exists?(:contacts, [:account_id, :source])
    add_index :contacts, [:account_id, :created_at],  name: 'idx_contacts_account_created_at'  unless index_exists?(:contacts, [:account_id, :created_at])
    add_index :contacts, :phone,                      name: 'idx_contacts_phone'               unless index_exists?(:contacts, :phone)

    # notifications — polling a cada 10s, filtro por read_at
    add_index :notifications, [:account_id, :read_at], name: 'idx_notifications_account_read_at' unless index_exists?(:notifications, [:account_id, :read_at])

    # appointments — relatórios por data
    add_index :appointments, [:account_id, :appointment_date], name: 'idx_appointments_account_date'   unless index_exists?(:appointments, [:account_id, :appointment_date])
    add_index :appointments, [:account_id, :status],           name: 'idx_appointments_account_status' unless index_exists?(:appointments, [:account_id, :status])

    # condominia — buscas da IA por bairro/cidade
    add_index :condominia, [:account_id, :neighborhood], name: 'idx_condominia_account_neighborhood' unless index_exists?(:condominia, [:account_id, :neighborhood])
    add_index :condominia, [:account_id, :status],       name: 'idx_condominia_account_status'       unless index_exists?(:condominia, [:account_id, :status])

    # scheduled_messages — job que busca pending por data
    add_index :scheduled_messages, [:status, :send_at], name: 'idx_scheduled_messages_status_send_at' unless index_exists?(:scheduled_messages, [:status, :send_at])

    # conversations — followup job filtra por inbox+status+last_activity
    add_index :conversations, [:inbox_id, :status], name: 'idx_conversations_inbox_status' unless index_exists?(:conversations, [:inbox_id, :status])
  end
end
