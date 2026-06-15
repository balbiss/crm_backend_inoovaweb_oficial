class AddJidAndAvatarUrlToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :jid, :string
    add_column :contacts, :avatar_url, :string
  end
end
