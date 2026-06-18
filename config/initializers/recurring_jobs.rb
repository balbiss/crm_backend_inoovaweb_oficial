Rails.application.config.after_initialize do
  next unless Rails.env.production? || Rails.env.development?
  next if defined?(Rails::Console) || File.basename($PROGRAM_NAME) == 'rake'

  begin
    CheckSnoozedConversationsJob.set(wait: 30.seconds).perform_later
  rescue => e
    Rails.logger.warn("Could not enqueue CheckSnoozedConversationsJob: #{e.message}")
  end
end
