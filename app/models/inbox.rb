class Inbox < ApplicationRecord
  belongs_to :account
  belongs_to :round_robin_group, optional: true
  has_many :conversations, dependent: :nullify
  has_many :inbox_members, dependent: :destroy
  has_many :users, through: :inbox_members, dependent: :destroy

  validate :followup_not_allowed_for_instagram

  def messaging_service
    case provider
    when 'instagram' then InstagramMessagingService.new(self)
    else WhatsappBaileysService.new(self)
    end
  end

  private

  def followup_not_allowed_for_instagram
    return unless provider == 'instagram' && followup_enabled?

    errors.add(:followup_enabled, 'não é permitido para o canal Instagram (janela de 24h da Meta)')
  end
end
