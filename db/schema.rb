# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_11_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "asaas_api_key"
    t.boolean "asaas_sandbox", default: false, null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.string "portal_token"
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.string "subscription_status"
    t.datetime "trial_ends_at"
    t.datetime "updated_at", null: false
    t.index ["portal_token"], name: "index_accounts_on_portal_token", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "appointments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "appointment_date"
    t.string "broker_name"
    t.bigint "condominium_id"
    t.bigint "contact_id", null: false
    t.datetime "created_at", null: false
    t.string "end_time"
    t.bigint "property_id"
    t.string "start_time"
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["account_id", "appointment_date"], name: "idx_appointments_account_date"
    t.index ["account_id", "status"], name: "idx_appointments_account_status"
    t.index ["account_id"], name: "index_appointments_on_account_id"
    t.index ["condominium_id"], name: "index_appointments_on_condominium_id"
    t.index ["contact_id"], name: "index_appointments_on_contact_id"
    t.index ["property_id"], name: "index_appointments_on_property_id"
    t.index ["user_id"], name: "index_appointments_on_user_id"
  end

  create_table "condominia", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "address"
    t.string "administrator"
    t.text "allotment_infrastructure"
    t.string "architecture"
    t.string "builder"
    t.string "building_type"
    t.string "built_area"
    t.string "cep"
    t.string "city"
    t.text "commercial_features"
    t.string "condominium_types"
    t.string "construction_progress"
    t.string "construction_year"
    t.string "country"
    t.datetime "created_at", null: false
    t.date "delivery_date"
    t.string "developer"
    t.boolean "government_plan"
    t.text "infrastructure"
    t.string "land_area"
    t.string "latitude"
    t.text "leisure_features"
    t.string "longitude"
    t.decimal "max_price"
    t.decimal "min_price"
    t.string "name"
    t.string "neighborhood"
    t.string "number"
    t.boolean "on_site_sales"
    t.string "reference_point"
    t.text "security_features"
    t.text "services"
    t.text "social_features"
    t.string "state"
    t.string "status"
    t.string "street"
    t.string "sub_type"
    t.string "tags"
    t.datetime "updated_at", null: false
    t.index ["account_id", "neighborhood"], name: "idx_condominia_account_neighborhood"
    t.index ["account_id", "status"], name: "idx_condominia_account_status"
    t.index ["account_id"], name: "index_condominia_on_account_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "address_complement"
    t.string "address_number"
    t.string "asaas_customer_id"
    t.string "avatar_url"
    t.text "bio"
    t.date "birth_date"
    t.string "cep"
    t.string "city"
    t.string "company_name"
    t.string "country"
    t.string "cpf"
    t.datetime "created_at", null: false
    t.jsonb "custom_attributes", default: {}
    t.integer "dependents"
    t.decimal "down_payment"
    t.string "email"
    t.decimal "fgts_balance"
    t.string "first_name"
    t.decimal "gross_income"
    t.string "instagram_id"
    t.string "intention"
    t.string "jid"
    t.string "last_name"
    t.string "name"
    t.string "neighborhood"
    t.string "phone"
    t.string "profession"
    t.string "source"
    t.string "state"
    t.string "status"
    t.string "street"
    t.string "temperature"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["account_id", "created_at"], name: "idx_contacts_account_created_at"
    t.index ["account_id", "jid"], name: "index_contacts_on_account_id_and_jid"
    t.index ["account_id", "source"], name: "idx_contacts_account_source"
    t.index ["account_id", "status"], name: "index_contacts_on_account_id_and_status"
    t.index ["account_id", "temperature"], name: "idx_contacts_account_temperature"
    t.index ["account_id"], name: "index_contacts_on_account_id"
    t.index ["account_id", "instagram_id"], name: "index_contacts_on_account_id_and_instagram_id"
    t.index ["asaas_customer_id"], name: "index_contacts_on_asaas_customer_id"
    t.index ["instagram_id"], name: "index_contacts_on_instagram_id"
    t.index ["jid"], name: "index_contacts_on_jid"
    t.index ["phone"], name: "index_contacts_on_phone"
    t.index ["user_id"], name: "index_contacts_on_user_id"
  end

  create_table "conversation_tags", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "tag_id", null: false
    t.index ["conversation_id", "tag_id"], name: "index_conversation_tags_on_conversation_and_tag", unique: true
    t.index ["conversation_id"], name: "index_conversation_tags_on_conversation_id"
    t.index ["tag_id"], name: "index_conversation_tags_on_tag_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.datetime "created_at", null: false
    t.integer "followup_count", default: 0
    t.bigint "inbox_id"
    t.datetime "last_activity_at"
    t.datetime "snoozed_until"
    t.string "source"
    t.integer "status", default: 0
    t.integer "unread_count", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["account_id", "status"], name: "index_conversations_on_account_id_and_status"
    t.index ["account_id"], name: "index_conversations_on_account_id"
    t.index ["contact_id"], name: "index_conversations_on_contact_id"
    t.index ["inbox_id", "status"], name: "idx_conversations_inbox_status"
    t.index ["inbox_id"], name: "index_conversations_on_inbox_id"
    t.index ["last_activity_at"], name: "index_conversations_on_last_activity_at"
    t.index ["status"], name: "index_conversations_on_status"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "global_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_global_settings_on_key", unique: true
  end

  create_table "inbox_members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "inbox_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["inbox_id", "user_id"], name: "index_inbox_members_on_inbox_id_and_user_id", unique: true
    t.index ["inbox_id"], name: "index_inbox_members_on_inbox_id"
    t.index ["user_id"], name: "index_inbox_members_on_user_id"
  end

  create_table "inboxes", force: :cascade do |t|
    t.bigint "account_id"
    t.boolean "ai_enabled", default: false
    t.string "ai_name"
    t.text "ai_prompt"
    t.float "ai_temperature", default: 0.7
    t.string "api_key"
    t.string "api_url"
    t.text "bot_prompt"
    t.datetime "created_at", null: false
    t.text "followup_closing_message"
    t.boolean "followup_enabled", default: false
    t.integer "followup_max_attempts", default: 3
    t.boolean "followup_send_closing_message", default: false
    t.integer "followup_wait_time_minutes", default: 120
    t.string "instagram_access_token"
    t.string "instagram_business_account_id"
    t.string "instagram_page_id"
    t.datetime "instagram_token_expires_at"
    t.string "instagram_username"
    t.string "name"
    t.text "out_of_office_message"
    t.string "phone_number"
    t.string "provider"
    t.bigint "round_robin_group_id"
    t.datetime "updated_at", null: false
    t.jsonb "working_hours", default: []
    t.boolean "working_hours_enabled", default: false
    t.index ["account_id"], name: "index_inboxes_on_account_id"
    t.index ["instagram_page_id"], name: "index_inboxes_on_instagram_page_id"
    t.index ["phone_number"], name: "index_inboxes_on_phone_number"
    t.index ["round_robin_group_id"], name: "index_inboxes_on_round_robin_group_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_private", default: false
    t.integer "sender_id"
    t.string "sender_type", null: false
    t.string "source_id"
    t.integer "status", default: 0
    t.text "text"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_messages_on_account_id"
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["sender_type", "sender_id"], name: "index_messages_on_sender_type_and_sender_id"
    t.index ["source_id"], name: "index_messages_on_source_id"
  end

  create_table "notes", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id"], name: "index_notes_on_account_id"
    t.index ["contact_id"], name: "index_notes_on_contact_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "link"
    t.string "message"
    t.datetime "read_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["account_id", "read_at"], name: "idx_notifications_account_read_at"
    t.index ["account_id"], name: "index_notifications_on_account_id"
  end

  create_table "properties", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "agent_name"
    t.string "agent_phone"
    t.date "auth_end_date"
    t.date "auth_start_date"
    t.integer "bathrooms"
    t.integer "bedrooms"
    t.integer "built_area"
    t.string "cep"
    t.string "city"
    t.string "code"
    t.string "complement"
    t.string "condo_name"
    t.string "country"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "exclusivity"
    t.string "iptu_condition"
    t.decimal "iptu_value"
    t.decimal "latitude"
    t.string "listing_type"
    t.decimal "longitude"
    t.string "neighborhood"
    t.string "number"
    t.string "owner_email"
    t.string "owner_name"
    t.string "owner_phone"
    t.string "owner_phone_type"
    t.integer "parking_spots"
    t.decimal "price"
    t.string "property_type"
    t.string "reference_point"
    t.integer "search_count", default: 0, null: false
    t.string "show_address_mode"
    t.string "state"
    t.string "status"
    t.string "street"
    t.integer "suites"
    t.string "title"
    t.integer "total_area"
    t.datetime "updated_at", null: false
    t.string "usage_type"
    t.bigint "user_id"
    t.index ["account_id", "bedrooms"], name: "idx_properties_account_bedrooms"
    t.index ["account_id", "listing_type"], name: "idx_properties_account_listing_type"
    t.index ["account_id", "neighborhood"], name: "idx_properties_account_neighborhood"
    t.index ["account_id", "price"], name: "idx_properties_account_price"
    t.index ["account_id", "status"], name: "idx_properties_account_status"
    t.index ["account_id"], name: "index_properties_on_account_id"
    t.index ["user_id"], name: "index_properties_on_user_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.text "auth_key", null: false
    t.datetime "created_at", null: false
    t.text "endpoint", null: false
    t.text "p256dh_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "round_robin_groups", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_round_robin_groups_on_account_id"
  end

  create_table "scheduled_messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "send_at"
    t.string "status", default: "pending"
    t.text "text"
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_scheduled_messages_on_conversation_id"
    t.index ["status", "send_at"], name: "idx_scheduled_messages_status_send_at"
  end

  create_table "support_ticket_messages", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "support_ticket_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["support_ticket_id"], name: "index_support_ticket_messages_on_support_ticket_id"
    t.index ["user_id"], name: "index_support_ticket_messages_on_user_id"
  end

  create_table "support_tickets", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.integer "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_support_tickets_on_account_id"
  end

  create_table "tags", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "color", default: "#6b7280"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_tags_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_tags_on_account_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "account_id"
    t.boolean "available_for_roundrobin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "department", default: "corretor", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "jti"
    t.string "last_name"
    t.jsonb "permissions", default: {}
    t.string "phone"
    t.integer "queue_position"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role"
    t.bigint "round_robin_group_id"
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
    t.index ["account_id", "available_for_roundrobin", "queue_position"], name: "index_users_on_account_roundrobin_queue"
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["department"], name: "index_users_on_department"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["round_robin_group_id"], name: "index_users_on_round_robin_group_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "appointments", "accounts"
  add_foreign_key "appointments", "condominia"
  add_foreign_key "appointments", "contacts"
  add_foreign_key "appointments", "properties"
  add_foreign_key "appointments", "users"
  add_foreign_key "condominia", "accounts"
  add_foreign_key "contacts", "accounts"
  add_foreign_key "contacts", "users"
  add_foreign_key "conversation_tags", "conversations"
  add_foreign_key "conversation_tags", "tags"
  add_foreign_key "conversations", "accounts"
  add_foreign_key "conversations", "contacts"
  add_foreign_key "conversations", "inboxes"
  add_foreign_key "conversations", "users"
  add_foreign_key "inbox_members", "inboxes"
  add_foreign_key "inbox_members", "users"
  add_foreign_key "inboxes", "accounts"
  add_foreign_key "inboxes", "round_robin_groups"
  add_foreign_key "messages", "accounts"
  add_foreign_key "messages", "conversations"
  add_foreign_key "notes", "accounts"
  add_foreign_key "notes", "contacts"
  add_foreign_key "notes", "users"
  add_foreign_key "notifications", "accounts"
  add_foreign_key "properties", "accounts"
  add_foreign_key "properties", "users"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "round_robin_groups", "accounts"
  add_foreign_key "scheduled_messages", "conversations"
  add_foreign_key "support_ticket_messages", "support_tickets"
  add_foreign_key "support_ticket_messages", "users"
  add_foreign_key "support_tickets", "accounts"
  add_foreign_key "tags", "accounts"
  add_foreign_key "users", "round_robin_groups"
end
