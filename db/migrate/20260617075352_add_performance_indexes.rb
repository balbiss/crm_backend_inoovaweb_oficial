class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # contacts.jid — usado em toda busca de webhook do WhatsApp
    add_index :contacts, :jid, name: 'index_contacts_on_jid' unless index_exists?(:contacts, :jid)

    # contacts.(account_id, jid) — busca por jid dentro de uma conta
    add_index :contacts, [:account_id, :jid], name: 'index_contacts_on_account_id_and_jid' unless index_exists?(:contacts, [:account_id, :jid])

    # contacts.status — filtro do Kanban
    add_index :contacts, [:account_id, :status], name: 'index_contacts_on_account_id_and_status' unless index_exists?(:contacts, [:account_id, :status])

    # messages.(conversation_id, created_at) — ordenação de mensagens por conversa
    add_index :messages, [:conversation_id, :created_at], name: 'index_messages_on_conversation_id_and_created_at' unless index_exists?(:messages, [:conversation_id, :created_at])

    # conversations.(account_id, status) — filtro de conversas por status
    add_index :conversations, [:account_id, :status], name: 'index_conversations_on_account_id_and_status' unless index_exists?(:conversations, [:account_id, :status])

    # conversations.last_activity_at — ordenação de conversas recentes
    add_index :conversations, :last_activity_at, name: 'index_conversations_on_last_activity_at' unless index_exists?(:conversations, :last_activity_at)

    # conversation_tags — busca de tags por conversa
    add_index :conversation_tags, [:conversation_id, :tag_id], unique: true, name: 'index_conversation_tags_on_conversation_and_tag' unless index_exists?(:conversation_tags, [:conversation_id, :tag_id])
  end
end
