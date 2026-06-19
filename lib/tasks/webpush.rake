namespace :webpush do
  desc "Gera as chaves VAPID para push notifications. Adicione ao docker-stack.yml e nunca mude depois."
  task generate_keys: :environment do
    key = Webpush.generate_key
    puts ""
    puts "Adicione estas variáveis ao docker-stack.yml (ambiente do crm_backend):"
    puts ""
    puts "  - VAPID_PUBLIC_KEY=#{key.public_key}"
    puts "  - VAPID_PRIVATE_KEY=#{key.private_key}"
    puts ""
    puts "E esta variável ao docker-stack.yml (ambiente do crm_frontend, para o VITE):"
    puts ""
    puts "  - VITE_VAPID_PUBLIC_KEY=#{key.public_key}"
    puts ""
    puts "ATENÇÃO: Gere as chaves UMA SÓ VEZ. Mudar invalida todas as assinaturas existentes."
  end
end
