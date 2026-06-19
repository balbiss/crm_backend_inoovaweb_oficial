class WebPushService
  VAPID = {
    subject:     "mailto:#{ENV.fetch('SMTP_USER', 'suporte@visitaia.com.br')}",
    public_key:  ENV.fetch('VAPID_PUBLIC_KEY',  ''),
    private_key: ENV.fetch('VAPID_PRIVATE_KEY', '')
  }.freeze

  def self.notify(user, title:, body:, url: '/conversas', tag: 'crm')
    return if VAPID[:public_key].blank? || VAPID[:private_key].blank?

    user.push_subscriptions.each do |sub|
      Webpush.payload_send(
        endpoint: sub.endpoint,
        message:  { title: title, body: body, url: url, tag: tag }.to_json,
        p256dh:   sub.p256dh_key,
        auth:     sub.auth_key,
        vapid:    VAPID
      )
    rescue Webpush::ExpiredSubscription, Webpush::InvalidSubscription
      sub.destroy
    rescue => e
      Rails.logger.error("WebPushService: #{e.message}")
    end
  end
end
