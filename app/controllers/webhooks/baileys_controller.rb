module Webhooks
  class BaileysController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def create
      # The baileys-api webhook payload typically contains events
      event = params[:event]
      payload = params[:payload] || params
      
      if event == 'messages.upsert'
        handle_messages_upsert(payload)
      elsif event == 'connection.update'
        handle_connection_update(payload)
      end

      render json: { status: 'ok' }
    rescue StandardError => e
      Rails.logger.error("Baileys webhook error: #{e.message}")
      render json: { status: 'error', message: e.message }, status: :internal_server_error
    end

    private

    def handle_connection_update(payload)
      phone_number = params[:phone]
      return if phone_number.blank?

      inbox = Inbox.find_by(phone_number: phone_number) || Inbox.find_by(phone_number: phone_number.delete('+'))
      return unless inbox

      data = payload[:data] || payload['data'] || {}
      
      # Salva o status e qr code no cache
      if data[:qrDataUrl].present?
        Rails.cache.write("inbox:#{inbox.id}:qr_code", data[:qrDataUrl], expires_in: 5.minutes)
      elsif data['qrDataUrl'].present?
        Rails.cache.write("inbox:#{inbox.id}:qr_code", data['qrDataUrl'], expires_in: 5.minutes)
      elsif data[:qr].present?
        Rails.cache.write("inbox:#{inbox.id}:qr_code", data[:qr], expires_in: 5.minutes)
      elsif data['qr'].present?
        Rails.cache.write("inbox:#{inbox.id}:qr_code", data['qr'], expires_in: 5.minutes)
      end

      connection_status = data[:connection] || data['connection']
      if connection_status.present?
        Rails.cache.write("inbox:#{inbox.id}:status", connection_status)
        # Limpa o QR do cache se conectado
        if connection_status == 'open'
          Rails.cache.delete("inbox:#{inbox.id}:qr_code")
        end
      end

      Rails.logger.info("Baileys webhook connection update for inbox #{inbox.id}: status=#{connection_status}, qr_present=#{(data[:qrDataUrl] || data['qrDataUrl']).present?}")

      # Envia via Action Cable em tempo real para o frontend
      ActionCable.server.broadcast("conversations_channel_#{inbox.account_id}", {
        event: 'inbox_updated',
        inbox_id: inbox.id,
        connection_status: connection_status || Rails.cache.read("inbox:#{inbox.id}:status") || 'close',
        qr_code: Rails.cache.read("inbox:#{inbox.id}:qr_code")
      })
    end

    def handle_messages_upsert(payload)
      data = payload[:data] || payload['data'] || payload
      messages = data[:messages] || data['messages'] || []
      
      messages.each do |msg|
        msg = msg.with_indifferent_access if msg.respond_to?(:with_indifferent_access)
        
        phone_number = params[:phone]
        clean_phone  = phone_number&.delete('+')
        inbox = Inbox.find_by(phone_number: phone_number) || Inbox.find_by(phone_number: clean_phone)
        return unless inbox

        remote_jid = msg.dig(:key, :remoteJid)
        next unless remote_jid
        
        # Ignorar mensagens de grupos
        next if remote_jid.include?('@g.us')

        # Tratamento de fromMe (Humano do nosso lado enviou mensagem)
        if msg.dig(:key, :fromMe)
          baileys_msg_id = msg.dig(:key, :id)
          # Se a mensagem já existe no banco, foi enviada pela IA — ignora o echo sem pausar a IA
          if baileys_msg_id.present? && Message.exists?(source_id: baileys_msg_id)
            next
          end
          # Se a IA sinaliza que está respondendo agora, também é echo da IA
          if inbox.ai_enabled && Rails.cache.read("ai_is_replying_#{inbox.id}_#{remote_jid}")
            next
          end
          # Chegou até aqui: é intervenção humana real → pausa a IA
          if inbox.ai_enabled
            Rails.logger.info("IA pausada para #{remote_jid} devido a intervenção humana (fromMe).")
            Rails.cache.write("ai_paused_#{inbox.id}_#{remote_jid}", Time.current.to_i)
            # Aplica etiqueta agente_off na conversa
            Thread.new do
              begin
                conv = inbox.conversations.joins(:contact).where(contacts: { jid: remote_jid }).first
                if conv
                  tag = conv.account.tags.find_or_create_by!(name: 'agente_off') { |t| t.color = '#f97316' }
                  conv.tags << tag unless conv.tags.include?(tag)
                  ActionCable.server.broadcast("conversations_channel_#{conv.account_id}", {
                    event: 'conversation_tags_updated',
                    conversation_id: conv.id,
                    tags: conv.tags.map { |t| { id: t.id, name: t.name, color: t.color } }
                  })
                end
              rescue => e
                Rails.logger.error("Erro ao aplicar tag agente_off: #{e.message}")
              end
            end
          end
          next
        end

        # Extração inteligente do telefone e JID real (lid vs s.whatsapp.net)
        key_data = msg[:key] || {}
        remote_jid_alt = key_data[:remoteJidAlt] || key_data['remoteJidAlt']

        contact_jid = remote_jid
        contact_phone = nil

        if remote_jid.include?('@s.whatsapp.net')
          contact_phone = remote_jid.split('@').first
        elsif remote_jid.include?('@lid')
          if remote_jid_alt.present? && remote_jid_alt.include?('@s.whatsapp.net')
            contact_phone = remote_jid_alt.split('@').first
          else
            contact_phone = remote_jid.split('@').first
          end
        else
          contact_phone = remote_jid.split('@').first
        end

        # Formatar telefone com '+' se for puramente numérico (para alinhar com o Chatwoot original)
        if contact_phone.present? && contact_phone.match?(/\A\d+\z/)
          contact_phone_formatted = "+#{contact_phone}"
        else
          contact_phone_formatted = contact_phone
        end
        
        # Get message text
        text = msg.dig(:message, :conversation) || msg.dig(:message, :extendedTextMessage, :text) || ''
        source_id = msg.dig(:key, :id)

        # Clique em anúncio (Instagram/Facebook Ads) chega sem texto próprio: o conteúdo
        # fica em contextInfo.externalAdReply, não no campo de texto normal. Sem isso, a
        # mensagem cai no fallback de "arquivo não suportado" e confunde a IA depois.
        if text.blank?
          ad_reply = msg.dig(:message, :extendedTextMessage, :contextInfo, :externalAdReply)
          if ad_reply.present?
            ad_title = ad_reply[:title].presence
            ad_body  = ad_reply[:body].presence
            ad_desc  = [ad_title, ad_body].compact.join(' — ').presence || 'um anúncio'
            text = "🔖 Cliente iniciou a conversa a partir de #{ad_desc}"
          end
        end

        Rails.logger.info("Incoming MSG Payload: #{msg.to_json}")

        next if Message.exists?(source_id: source_id)

        # Usa a conta do próprio inbox (evita fallback para Account.first errado)
        account = inbox.account

        # Find or create contact
        contact = Contact.find_or_create_by(phone: contact_phone_formatted, account_id: account.id) do |c|
          c.name = msg[:pushName] || msg['pushName'] || contact_phone_formatted
          c.jid = contact_jid
          c.source = 'WhatsApp'
        end

        # Ignora contatos bloqueados
        if contact.status == 'blocked'
          Rails.logger.info("Mensagem ignorada: contato #{contact_phone_formatted} está bloqueado")
          return head :ok
        end

        # Atualiza o JID se estava vazio (para contatos antigos)
        if contact.jid != contact_jid
          contact.update(jid: contact_jid)
        end

        # Buscar foto de perfil em background (se não tiver foto salva)
        if contact.avatar_url.blank?
          Thread.new do
            begin
              target_jid = nil
              if remote_jid.include?('@s.whatsapp.net')
                target_jid = remote_jid
              elsif remote_jid.include?('@lid') && remote_jid_alt.present? && remote_jid_alt.include?('@s.whatsapp.net')
                target_jid = remote_jid_alt
              end

              if target_jid.present?
                url = WhatsappBaileysService.new(inbox).fetch_profile_picture_url(target_jid)
                if url.present?
                  contact.update(avatar_url: url)
                end
              end
            rescue => e
              Rails.logger.error("Failed to fetch profile picture for #{target_jid}: #{e.message}")
            end
          end
        end

        # Find or create conversation
        conversation = Conversation.find_or_create_by(contact: contact, inbox: inbox) do |conv|
          conv.status = :open
          conv.account = account
        end

        # Save message
        message_record = Message.create!(
          account: conversation.account,
          conversation: conversation,
          text: text,
          sender_type: 'Contact',
          sender_id: contact.id,
          source_id: source_id,
          status: :delivered
        )

        # Tratar a mídia
        media_data = nil
        if payload.is_a?(Hash) && payload[:extra].is_a?(Hash) && payload[:extra][:media].is_a?(Hash)
          media_data = payload[:extra][:media][source_id] || payload[:extra][:media][source_id.to_sym]
        elsif payload.is_a?(Hash) && payload['extra'].is_a?(Hash) && payload['extra']['media'].is_a?(Hash)
          media_data = payload['extra']['media'][source_id]
        end

        msg_obj = msg[:message] || msg['message'] || {}
        media_type_key = msg_obj.keys.find { |k| k.to_s.end_with?('Message') && k.to_s != 'extendedTextMessage' }
        
        if media_type_key
          media_info = msg_obj[media_type_key]
          mimetype = media_info[:mimetype] || media_info['mimetype'] || 'application/octet-stream'
          
          extension = mimetype.split('/').last&.split(';')&.first || 'bin'
          filename = "#{source_id}.#{extension}"
          
          decoded_media = nil
          if media_data.present?
            require 'base64'
            decoded_media = Base64.decode64(media_data)
          else
            api_url = inbox.api_url.presence || ENV['BAILEYS_API_URL'].presence || 'http://baileys-api:3025'
            api_key = inbox.api_key.presence || ENV['BAILEYS_API_KEY'].presence || 'innovaweb2025'
            uri = URI.parse(api_url)
            uri.path = "/media/#{source_id}"
            req = Net::HTTP::Get.new(uri)
            req["x-api-key"] = api_key
            
            begin
              res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
                http.request(req)
              end
              decoded_media = res.body if res.is_a?(Net::HTTPSuccess)
            rescue => e
              Rails.logger.error("Failed to download media for message #{source_id}: #{e.message}")
            end
          end
          
          if decoded_media.present?
            message_record.attachment.attach(
              io: StringIO.new(decoded_media),
              filename: filename,
              content_type: mimetype
            )
            
            caption = media_info[:caption] || media_info['caption']
            message_record.update(text: caption) if caption.present? && message_record.text.blank?

            if mimetype.start_with?('audio/') && inbox.ai_enabled
              begin
                transcription = AiAssistantService.transcribe_audio(decoded_media, filename, inbox)
                message_record.update(text: "[Áudio Transcrito] #{transcription}") if transcription.present?
              rescue => e
                Rails.logger.error("Erro no Whisper: #{e.message}")
              end
            end

            message_record.update(text: '📎 Anexo recebido') if message_record.text.blank?
          else
            message_record.update(text: '📎 Arquivo não pôde ser baixado') if message_record.text.blank?
          end
        elsif message_record.text.blank?
          # Fallback se não tiver texto nem mídia
          message_record.update(text: '📎 Arquivo não suportado ou vazio')
        end

        # ===== MOTOR DE INTELIGÊNCIA ARTIFICIAL =====
        if inbox.ai_enabled
          is_paused = Rails.cache.read("ai_paused_#{inbox.id}_#{remote_jid}")

          if is_paused
            Rails.logger.info("IA pulou atendimento para #{remote_jid} porque está em cooldown (Humano assumiu).")
          elsif conversation.status == 'resolved'
            # Cliente voltou depois de conversa encerrada — reabrir para o corretor
            conversation.update!(status: :open)
            # Pausa a IA 30 min para o corretor ter prioridade no atendimento do retorno
            Rails.cache.write("ai_paused_#{inbox.id}_#{remote_jid}", Time.current.to_i, expires_in: 30.minutes)
            ActionCable.server.broadcast("conversations_channel_#{conversation.account_id}", {
              event:        'conversation_updated',
              conversation: { id: conversation.id, status: 'open', snoozed_until: nil }
            })
            Rails.logger.info("Conversa #{conversation.id} reaberta automaticamente (cliente retornou após encerramento).")
          else
            # Conversa open ou snoozed: a IA deve responder
            if conversation.status == 'snoozed'
              # Cliente enviou mensagem durante o adiamento — cancelar snooze
              conversation.update!(status: :open, snoozed_until: nil)
              ActionCable.server.broadcast("conversations_channel_#{conversation.account_id}", {
                event:           'snooze_expired',
                conversation_id: conversation.id,
                contact_name:    contact.name.presence || contact.phone,
                reason:          'client_message'
              })
              ActionCable.server.broadcast("conversations_channel_#{conversation.account_id}", {
                event:        'conversation_updated',
                conversation: { id: conversation.id, status: 'open', snoozed_until: nil }
              })
            end

            # Lógica de Debounce (Agrupamento de 8 segundos)
            debounce_key = "debounce_ai_#{inbox.id}_#{remote_jid}"
            current_time = Time.now.to_f
            Rails.cache.write(debounce_key, current_time)

            # Processar com a IA em background para não travar o Webhook
            Thread.new do
              begin
                sleep 8 # Espera 8 segundos para agrupar mensagens sucessivas

                # Se o valor no cache ainda for o mesmo, significa que não chegou nova mensagem nesses 8s
                if Rails.cache.read(debounce_key) == current_time
                  Rails.logger.info("Iniciando AiAssistantService para a conversa #{conversation.id}")

                  # Chama a OpenAI e resolve as tools
                  ai_service = AiAssistantService.new(inbox, conversation)
                  ai_response_text = ai_service.process_message

                  if ai_response_text.present?
                    # Avisamos ao sistema que a IA está respondendo para não dar trigger no fromMe
                    Rails.cache.write("ai_is_replying_#{inbox.id}_#{remote_jid}", true, expires_in: 60.seconds)

                    # Separar resposta em múltiplos balões (parágrafos)
                    paragraphs = ai_response_text.is_a?(Array) ? ai_response_text : ai_response_text.split("\n\n").reject(&:blank?)

                    # Usa o JID @s.whatsapp.net para presence (LID não mostra digitando no WhatsApp)
                    presence_jid = (remote_jid_alt.presence && remote_jid_alt.include?('@s.whatsapp.net')) ? remote_jid_alt : remote_jid

                    paragraphs.each do |paragraph|
                      # Simulador de digitando
                      WhatsappBaileysService.new(inbox).send_presence_update(presence_jid, 'composing')

                      # Calcula tempo de digitação com base no tamanho (mais realista)
                      typing_time = [(paragraph.length / 15.0).round, 3].max
                      typing_time = [typing_time, 15].min
                      sleep typing_time

                      # Renova o aviso para garantir que o echo da msg dê tempo de chegar
                      Rails.cache.write("ai_is_replying_#{inbox.id}_#{remote_jid}", true, expires_in: 30.seconds)

                      # Para de digitar
                      WhatsappBaileysService.new(inbox).send_presence_update(presence_jid, 'paused')

                      # Envia a resposta de volta pro WhatsApp e captura o ID do Baileys
                      baileys_id = WhatsappBaileysService.new(inbox).send_message(remote_jid, paragraph.strip)

                      # Salva a mensagem da IA usando o ID do Baileys como source_id
                      # para que o echo fromMe seja reconhecido e não ative o cooldown
                      Message.create!(
                        account: conversation.account,
                        conversation: conversation,
                        text: paragraph.strip,
                        sender_type: 'User',
                        sender_id: nil,
                        source_id: baileys_id.present? ? baileys_id : "ai_#{SecureRandom.hex(8)}",
                        status: :delivered
                      )
                    end
                  end
                else
                  Rails.logger.info("Debounce cancelou a execução da IA (nova mensagem recebida) para #{remote_jid}")
                end
              rescue => e
                Rails.logger.error("Erro fatal no AiAssistantService: #{e.message}")
              end
            end
          end
        end
        # ============================================

      end
    end
  end
end
