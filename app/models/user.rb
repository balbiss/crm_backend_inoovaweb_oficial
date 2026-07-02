class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  belongs_to :account, optional: true

  has_many :support_tickets
  has_many :support_ticket_messages, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :contacts, dependent: :nullify
  has_many :conversations, dependent: :nullify
  has_many :properties, dependent: :nullify
  has_many :appointments, dependent: :nullify
  has_many :push_subscriptions, dependent: :destroy
  has_many :inbox_members, dependent: :destroy
  has_many :assigned_inboxes, through: :inbox_members, source: :inbox

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  enum :role, { atendente: 0, empresa: 1, admin: 2 }
  def active_for_authentication?
    super && status == 'active'
  end

  def inactive_message
    status == 'active' ? super : :account_inactive
  end

  # Helpers for permissions JSON
  def has_permission?(key)
    permissions.present? && permissions[key.to_s] == true
  end
end
