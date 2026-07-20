class AiFollowupJob < ApplicationJob
  queue_as :default

  def perform
    # Encontra inboxes com followup ativado (defensivo: Instagram nunca deve
    # rodar follow-up automático, mesmo que a validação do model seja contornada)
    Inbox.where(followup_enabled: true, provider: 'baileys').find_each do |inbox|
      process_inbox(inbox)
    end
  end

  private

  def process_inbox(inbox)
    wait_time = inbox.followup_wait_time_minutes || 120
    max_attempts = inbox.followup_max_attempts || 3
    threshold_time = wait_time.minutes.ago

    # Encontra conversas abertas, ainda não atribuídas a um corretor (user_id
    # nil) e associadas àquele inbox, onde a última atividade foi antes do
    # limite de espera. Uma vez transferida pra um corretor, o resgate
    # automático deixa de fazer sentido -- vira responsabilidade humana.
    inbox.conversations.where(status: :open, user_id: nil).where("last_activity_at < ?", threshold_time).find_each do |conversation|
      
      # Se a última mensagem foi do lead, o bot q demorou pra responder, não é caso de follow-up.
      # Só damos follow-up quando nós (User/Bot) falamos por último e o lead deixou no vácuo.
      last_message = conversation.messages.order(created_at: :asc).last
      next if last_message.nil? || last_message.sender_type == 'Contact'

      if conversation.followup_count.to_i < max_attempts
        generate_and_send_followup(inbox, conversation)
      else
        mark_as_cold(conversation)
      end
    end
  end

  def generate_and_send_followup(inbox, conversation)
    api_key = GlobalSetting.fetch('openai_api_key').presence || ENV['OPENAI_API_KEY']
    return unless api_key

    client = OpenAI::Client.new(access_token: api_key)

    recent_messages = conversation.messages.order(created_at: :asc).last(15)
    
    chat_history = recent_messages.map do |msg|
      role = msg.sender_type == 'Contact' ? 'user' : 'assistant'
      { role: role, content: msg.text || "📎 [Mídia]" }
    end

    base_prompt = inbox.ai_prompt || "Você é a inteligência artificial da imobiliária."

    system_prompt = <<~PROMPT
      #{base_prompt}
      
      -----------------
      [INSTRUÇÃO DE RESGATE (FOLLOW-UP)]
      O cliente parou de responder há algumas horas.
      Sua tarefa agora é criar UMA ÚNICA MENSAGEM MUITO CURTA (máximo de 15 a 20 palavras) para puxar assunto novamente.
      Mantenha EXATAMENTE a mesma personalidade e as regras do seu comportamento base acima.
      Seja super sutil, direta e amigável. Pergunte se ficou alguma dúvida, se ele pensou melhor ou se quer retomar de onde pararam.
      NUNCA mande um textão longo. NUNCA se apresente de novo como se fosse a primeira vez.
      Aja como se vocês estivessem conversando e ele simplesmente esqueceu de responder a última mensagem.
      RETORNE APENAS O TEXTO DA MENSAGEM E MAIS NADA.
    PROMPT

    begin
      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: chat_history + [{ role: "system", content: system_prompt }],
          temperature: 0.7
        }
      )
      
      followup_text = response.dig("choices", 0, "message", "content")
      
      if followup_text.present?
        # Enviar via Baileys
        baileys_service = WhatsappBaileysService.new(inbox)
        remote_jid = conversation.contact.jid || conversation.contact.phone
        baileys_id = baileys_service.send_message(remote_jid, followup_text)

        # Salvar mensagem usando o ID do Baileys como source_id, para que o
        # eco (fromMe) desta mensagem seja reconhecido no webhook e não seja
        # confundido com intervenção humana (o que pausava a IA e aplicava
        # a tag agente_off sem atribuir a nenhum corretor).
        Message.create!(
          account: conversation.account,
          conversation: conversation,
          text: followup_text,
          sender_type: 'User',
          sender_id: nil, # Indica que foi o bot
          source_id: baileys_id.presence || "followup_#{SecureRandom.hex(8)}",
          status: :delivered
        )

        # Atualizar contagem e timestamp para iniciar novo ciclo de contagem
        conversation.update_columns(
          followup_count: conversation.followup_count.to_i + 1,
          last_activity_at: Time.current
        )
      end

    rescue StandardError => e
      Rails.logger.error("Error generating followup: #{e.message}")
    end
  end

  def mark_as_cold(conversation)
    inbox = conversation.inbox
    
    # Enviar mensagem de encerramento se configurado
    if inbox.followup_send_closing_message? && inbox.followup_closing_message.present?
      begin
        baileys_service = WhatsappBaileysService.new(inbox)
        remote_jid = conversation.contact.jid || conversation.contact.phone
        baileys_id = baileys_service.send_message(remote_jid, inbox.followup_closing_message)

        Message.create!(
          account: conversation.account,
          conversation: conversation,
          text: inbox.followup_closing_message,
          sender_type: 'User',
          sender_id: nil,
          source_id: baileys_id.presence || "closing_#{SecureRandom.hex(8)}",
          status: :delivered
        )
      rescue StandardError => e
        Rails.logger.error("Error sending closing message: #{e.message}")
      end
    end

    # Marcar lead como frio
    contact = conversation.contact
    contact.update(temperature: 'Frio')
    
    # Adicionar nota ao lead
    Note.create!(
      account: conversation.account,
      contact: contact,
      user_id: conversation.user_id || contact.user_id || conversation.account.users.first&.id,
      content: "O sistema realizou #{conversation.followup_count} tentativas de follow-up automático sem sucesso. O lead parou de responder e foi esfriado."
    )

    # Resolve a conversa para sair da fila de atendimento
    conversation.update_columns(
      status: :resolved,
      followup_count: 0
    )
  end
end
