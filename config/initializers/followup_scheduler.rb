Thread.new do
  # Aguarda o Rails inicializar completamente antes de começar
  sleep 30

  loop do
    begin
      AiFollowupJob.perform_later
    rescue => e
      Rails.logger.error("FollowupScheduler error: #{e.message}")
    end

    sleep 10 * 60 # Executa a cada 10 minutos
  end
end
