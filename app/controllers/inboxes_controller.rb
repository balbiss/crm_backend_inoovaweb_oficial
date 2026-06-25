require_relative '../services/whatsapp_baileys_service'

class InboxesController < ApplicationController
  before_action :set_inbox, only: %i[ show update destroy qr_code status generate_prompt ]
  # Corretores podem ler inboxes e ver status (para filtrar conversas por canal).
  # Apenas o dono gerencia: criar, editar, remover, escanear QR, gerar prompt de IA.
  before_action :require_owner!, only: %i[ create update destroy qr_code generate_prompt ]

  def index
    @inboxes = current_user.account.inboxes
    render json: @inboxes
  end

  def show
    render json: @inbox
  end

  def create
    @inbox = current_user.account.inboxes.build(inbox_params)

    if @inbox.save
      if @inbox.provider == 'baileys'
        webhook_url = "#{ENV.fetch('API_HOST', 'http://localhost:3000')}/webhooks/baileys"
        service = WhatsappBaileysService.new(@inbox)
        # Attempt to create the connection in the external Baileys API
        service.create_connection(webhook_url) rescue StandardError
      end
      
      render json: @inbox, status: :created
    else
      render json: @inbox.errors, status: :unprocessable_entity
    end
  end

  def update
    if @inbox.update(inbox_params)
      render json: @inbox
    else
      render json: @inbox.errors, status: :unprocessable_entity
    end
  end

  def qr_code
    baileys = WhatsappBaileysService.new(@inbox)
    qr = baileys.fetch_qr_code
    
    if qr.nil?
      status = Rails.cache.read("inbox:#{@inbox.id}:status")
      unless %w[connecting open].include?(status)
        baileys.delete_connection rescue nil
        sleep 0.5
        webhook_url = "#{ENV.fetch('API_HOST', 'http://localhost:3000')}/webhooks/baileys"
        baileys.create_connection(webhook_url) rescue nil
        sleep 2.0
        qr = baileys.fetch_qr_code
      end
    end

    if qr
      render json: { qr_code: qr }
    else
      render json: { qr_code: nil, message: 'QR Code não disponível. Tente novamente em instantes.' }
    end
  end

  def status
    baileys = WhatsappBaileysService.new(@inbox)
    connected = baileys.connected?
    render json: { connected: connected }
  end

  def destroy
    conv_count = @inbox.conversations.count
    contact_count = @inbox.conversations.joins(:contact).select('contacts.id').distinct.count

    begin
      WhatsappBaileysService.new(@inbox).delete_connection
    rescue StandardError => e
      Rails.logger.error("Failed to delete connection in Baileys: #{e.message}")
    end

    # Preserva histórico: conversations ficam com inbox_id = null (dependent: :nullify)
    @inbox.destroy!

    head :no_content, headers: {
      'X-Preserved-Conversations' => conv_count.to_s,
      'X-Preserved-Contacts' => contact_count.to_s
    }
  end

  def generate_prompt
    data = params.require(:prompt_data).permit(:identity, :institutional, :faq, :greeting_message, :sdr_rules, :routing_rules, :ai_role, :allow_scheduling, :use_whatsapp_name, :emoji_usage, :prohibited_actions)
    
    system_prompt = <<~PROMPT
      Você é um Engenheiro de Prompts especialista em IA para Imobiliárias.
      Sua tarefa é criar um System Prompt detalhado, persuasivo e à prova de falhas para a IA de uma imobiliária, baseado nas informações fornecidas.
      O prompt gerado será usado como a diretriz de comportamento primária da IA.
      Sempre retorne APENAS o texto do prompt final, sem introduções ou explicações.
    PROMPT
    
    role_instruction = data[:ai_role] == 'sdr_only' ? "ATUAÇÃO RESTRITA A SDR: A IA NÃO pode ofertar imóveis aleatórios. O objetivo é APENAS qualificar o lead." : "ATUAÇÃO COMPLETA: A IA atua como SDR e como Corretora, podendo qualificar, pesquisar imóveis no banco e ofertar de forma vendedora."
    schedule_instruction = data[:allow_scheduling] ? "AGENDAMENTO AUTOMÁTICO: A IA PODE e DEVE realizar o agendamento automatizado no sistema quando o cliente quiser visitar." : "SEM AGENDAMENTO: A IA NÃO DEVE prometer agendamento automatizado. O agendamento é feito pelo corretor humano, a IA deve apenas anotar o interesse e transferir o atendimento."
    name_instruction = data[:use_whatsapp_name] ? "NOME DO CLIENTE E TELEFONE: O sistema já fornecerá o nome do cliente. Inicie o atendimento chamando-o pelo nome. NUNCA pergunte qual é o nome. Como JÁ ESTÃO no WhatsApp, NUNCA PERGUNTE O TELEFONE DE CONTATO, você já tem essa informação implicitamente." : "NOME DO CLIENTE E TELEFONE: Pergunte o nome do cliente de forma educada no início. No entanto, como já estão conversando pelo WhatsApp, NUNCA PERGUNTE O TELEFONE DE CONTATO."
    
    emoji_instruction = case data[:emoji_usage]
                        when 'none' then "PROIBIDO USO DE EMOJIS: Não utilize emojis em nenhuma circunstância. Mantenha a comunicação estritamente em texto limpo."
                        when 'lots' then "USO FREQUENTE DE EMOJIS: Utilize bastantes emojis para tornar a conversa muito descontraída, calorosa e jovem."
                        else "USO MODERADO DE EMOJIS: Utilize emojis de forma equilibrada e profissional para dar um tom amigável, sem exagerar."
                        end
                        
    prohibitions_instruction = data[:prohibited_actions].present? ? "AÇÕES ESTRITAMENTE PROIBIDAS (NUNCA FAÇA ISSO): #{data[:prohibited_actions]}" : "AÇÕES PROIBIDAS: Nenhuma extra."
    greeting_instruction = data[:greeting_message].present? ? "MENSAGEM DE SAUDAÇÃO EXATA (Primeiro Contato): Use exatamente esta mensagem quando o cliente entrar em contato pela primeira vez: \"#{data[:greeting_message]}\"" : "MENSAGEM DE SAUDAÇÃO: Crie uma saudação natural e acolhedora alinhada com a identidade e tom de voz definidos acima."

    user_content = <<~USER
      Crie o prompt usando estas diretrizes:
      1. Identidade e Tom de Voz: #{data[:identity]}
      2. Institucional (Horários/Diferenciais): #{data[:institutional]}
      3. FAQ: #{data[:faq]}
      4. #{greeting_instruction}
      5. Modo de Atuação: #{role_instruction}
      6. Regras de Agendamento: #{schedule_instruction}
      7. Tratamento de Contato: #{name_instruction}
      8. Estilo de Comunicação: #{emoji_instruction}
      9. Linhas Vermelhas: #{prohibitions_instruction}
      10. Regras de SDR (Dados obrigatórios para coletar): #{data[:sdr_rules]}
      11. Regras de Transbordo (Quando transferir para humano ou agendar visita): #{data[:routing_rules]}

      Certifique-se de que o prompt instrua a IA a ser natural, não robótica, e seguir rigorosamente as restrições de agendamento, atendimento e as regras estritas de nunca perguntar o telefone.
    USER

    begin
      api_key = GlobalSetting.fetch('openai_api_key').presence || ENV['OPENAI_API_KEY']
      client = OpenAI::Client.new(access_token: api_key)
      
      response = client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: user_content }
          ],
          temperature: 0.7
        }
      )
      
      generated_text = response.dig("choices", 0, "message", "content")
      render json: { prompt: generated_text }
    rescue StandardError => e
      Rails.logger.error("Error generating prompt: #{e.message}")
      render json: { error: "Erro ao gerar prompt na OpenAI." }, status: :unprocessable_entity
    end
  end

  private
    def set_inbox
      @inbox = current_user.account.inboxes.find(params.expect(:id))
    end

    def inbox_params
      params.require(:inbox).permit(:name, :provider, :phone_number, :api_url, :api_key, :bot_prompt, :ai_enabled, :ai_name, :ai_prompt, :ai_temperature, :working_hours_enabled, :out_of_office_message, :followup_enabled, :followup_max_attempts, :followup_wait_time_minutes, :followup_send_closing_message, :followup_closing_message, working_hours: [:day, :open, :start, :end])
    end
end
