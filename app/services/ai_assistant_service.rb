require 'openai'

class AiAssistantService
  def initialize(inbox, conversation)
    @inbox = inbox
    @conversation = conversation
    api_key = GlobalSetting.find_by(key: 'openai_api_key')&.value.presence || ENV['OPENAI_API_KEY']
    @client = OpenAI::Client.new(access_token: api_key)
  end

  def self.transcribe_audio(media_data, filename, inbox)
    api_key = GlobalSetting.find_by(key: 'openai_api_key')&.value.presence || ENV['OPENAI_API_KEY']
    client = OpenAI::Client.new(access_token: api_key)
    
    # Precisamos criar um arquivo temporário para enviar pro multipart faraday da OpenAI
    tempfile = Tempfile.new([filename.split('.').first, ".#{filename.split('.').last}"])
    tempfile.binmode
    tempfile.write(media_data)
    tempfile.rewind

    response = client.audio.transcribe(
      parameters: {
        model: "whisper-1",
        file: File.open(tempfile.path, "rb")
      }
    )
    
    tempfile.close
    tempfile.unlink
    
    response["text"]
  end

  def process_message
    # 1. Recuperar histórico da conversa
    messages = build_message_history

    # 2. Definir o comportamento da IA (System Prompt)
    system_prompt = {
      role: "system",
      content: build_system_prompt
    }

    # 3. Enviar para a OpenAI com Tools
    response = @client.chat(
      parameters: {
        model: "gpt-4o",
        messages: [system_prompt] + messages,
        temperature: @inbox.ai_temperature || 0.7,
        tools: defined_tools,
        tool_choice: "auto"
      }
    )

    text = handle_response(response, messages)
    text.present? ? split_into_messages(text) : []
  end

  private

  def split_into_messages(text)
    return [text] if text.length < 80 # Não divide mensagens curtas
    
    prompt = <<~PROMPT
      Você é um agente que simula o comportamento humano ao enviar mensagens no WhatsApp. 
      Seu objetivo é pegar uma mensagem longa recebida como entrada e dividi-la em múltiplas mensagens menores — sem alterar as palavras do conteúdo original — apenas separando em partes naturais, como um humano faria ao digitar e enviar aos poucos.
      
      REGRAS:
      - Não reescreva o conteúdo. Apenas separe em mensagens menores respeitando a pontuação e pausas naturais.
      - As divisões devem parecer naturais.
      - Sempre retorne como um JSON com o campo "mensagens" que é um array de strings.
      - Remova vírgulas e pontos finais no final das mensagens, quando soar mais natural para o chat.
      - Tente manter cada mensagem entre 1 a 4 frases no máximo.
      - NUNCA QUEBRE A MENSAGEM EM MAIS DE 5 PARTES.
      - Mantenha itens de lista na mesma mensagem. NUNCA quebre listas em múltiplas mensagens.
    PROMPT
    
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: prompt },
          { role: "user", content: text }
        ],
        temperature: 0.3
      }
    )
    
    json_str = response.dig("choices", 0, "message", "content")
    JSON.parse(json_str)["mensagens"] || [text]
  rescue => e
    Rails.logger.error("Erro ao dividir mensagem em blocos: #{e.message}")
    [text]
  end

  def build_message_history
    recent_messages = @conversation.messages.order(created_at: :asc).last(40)
    
    recent_messages.map do |msg|
      role = msg.sender_type == 'Contact' ? 'user' : 'assistant'
      { role: role, content: msg.text || "📎 [Mídia/Anexo]" }
    end
  end

  def build_system_prompt
    base_prompt = @inbox.ai_prompt.presence || "Você é uma assistente virtual prestativa."
    
    current_time = Time.current.in_time_zone('America/Sao_Paulo')
    dias_semana = %w[Domingo Segunda-feira Terça-feira Quarta-feira Quinta-feira Sexta-feira Sábado]
    dia_semana = dias_semana[current_time.wday]
    date_info = "Hoje é #{dia_semana}, #{current_time.strftime('%d/%m/%Y')}. O horário atual é #{current_time.strftime('%H:%M')}."
    
    contact_name = @conversation.contact.name.presence || "Cliente (nome desconhecido)"
    contact_phone = @conversation.contact.phone.presence || "Telefone desconhecido"
    contact_info = "Você está conversando com: #{contact_name}. Número do WhatsApp: #{contact_phone}."
    
    prompt = "#{base_prompt}\nSeu nome é #{@inbox.ai_name || 'Assistente'}. Você atende clientes de uma imobiliária. Seja muito humana, empática e natural.\n[CONTEXTO TEMPORAL]: #{date_info} (Sempre use essa data e hora reais como base).\n[DADOS DO CLIENTE]: #{contact_info}"
    
    status = @conversation.contact.status || 'lead'
    
    case status
    when 'lead'
      prompt += "\n[FASE DE PRÉ-VENDA (SDR)]: Você está atuando como Recepcionista/SDR. O lead acabou de chegar. Seu ÚNICO objetivo é descobrir o que o cliente procura (bairro, valor, quartos) ou a urgência dele. NUNCA tente vender imóveis ou agendar visitas. Apenas acolha, engaje e qualifique. Sempre que entender o que ele procura, use a ferramenta 'qualify_lead' para atualizar a intenção no CRM e avance o lead para 'visit' usando a ferramenta 'move_kanban_card'."
    when 'visit', 'atendimento'
      prompt += "\n[FASE DE ATENDIMENTO/VENDAS]: Você está atuando como Corretora Digital. O lead já foi qualificado. Seu foco agora é usar a busca de imóveis ('search_properties'), apresentar opções de forma encantadora e agendar visitas ('create_appointment').\n[REGRAS DE APRESENTAÇÃO DE IMÓVEIS]: Quando apresentar um imóvel, NUNCA use formato de lista robótica. Descreva o imóvel de forma fluida, conversacional e vendedora no meio do texto, como um bom corretor faria."
    when 'proposal', 'won'
      prompt += "\n[FASE DE FECHAMENTO]: Você está atuando no pós-visita/negociação. Foque em tirar dúvidas documentais e financeiras. Não oferte novos imóveis para não desfocar a venda."
    else
      # Default fallback
      prompt += "\n[QUALIFICAÇÃO]: Sempre que entender o que o cliente procura, use a ferramenta 'qualify_lead'."
    end
    
    prompt
  end

  def defined_tools
    status = @conversation.contact.status || 'lead'
    
    qualify_tool = {
      type: "function",
      function: {
        name: "qualify_lead",
        description: "Qualifica o lead, atualizando sua temperatura de compra e detalhando sua real intenção/necessidade.",
        parameters: {
          type: "object",
          properties: {
            temperature: { type: "string", enum: ["Frio", "Morno", "Quente"], description: "Temperatura do lead (Frio = só pesquisando, Morno = interessado, Quente = quer comprar logo)." },
            intention: { type: "string", description: "Descrição detalhada do que o cliente quer (ex: Busca apartamento de 2 quartos na Cidade Nova, até R$ 500 mil)." }
          },
          required: ["temperature", "intention"]
        }
      }
    }
    
    search_tool = {
      type: "function",
      function: {
        name: "search_properties",
        description: "Pesquisa imóveis no banco de dados da imobiliária com base em critérios.",
        parameters: {
          type: "object",
          properties: {
            neighborhood: { type: "string", description: "Bairro desejado" },
            bedrooms: { type: "integer", description: "Número de quartos" },
            max_price: { type: "integer", description: "Preço máximo em reais" }
          }
        }
      }
    }
    
    appointment_tool = {
      type: "function",
      function: {
        name: "create_appointment",
        description: "Agenda uma visita para o lead em um imóvel específico.",
        parameters: {
          type: "object",
          properties: {
            property_id: { type: "integer", description: "ID do imóvel" },
            date: { type: "string", description: "Data desejada (YYYY-MM-DD)" },
            time: { type: "string", description: "Hora desejada (HH:MM)" }
          },
          required: ["property_id", "date"]
        }
      }
    }
    
    photos_tool = {
      type: "function",
      function: {
        name: "send_property_photos",
        description: "Envia as fotos de um imóvel específico para o cliente no WhatsApp.",
        parameters: {
          type: "object",
          properties: {
            property_id: { type: "integer", description: "ID do imóvel avulso (Property)" }
          },
          required: ["property_id"]
        }
      }
    }
    
    kanban_tool = {
      type: "function",
      function: {
        name: "move_kanban_card",
        description: "Atualiza o estágio do cliente no funil de vendas (Kanban).",
        parameters: {
          type: "object",
          properties: {
            stage: { type: "string", enum: ["lead", "visit", "proposal", "won"], description: "Novo estágio do lead. Valores: 'lead' (Novos Leads), 'visit' (Visita Agendada), 'proposal' (Proposta Feita), 'won' (Negócio Fechado)" }
          },
          required: ["stage"]
        }
      }
    }
    
    case status
    when 'lead'
      [qualify_tool, kanban_tool]
    when 'visit', 'atendimento'
      [search_tool, photos_tool, appointment_tool, kanban_tool]
    when 'proposal', 'won'
      [kanban_tool]
    else
      [qualify_tool, search_tool, photos_tool, appointment_tool, kanban_tool]
    end
  end

  def handle_response(response, messages)
    choice = response.dig("choices", 0, "message")
    
    if choice["tool_calls"]
      # Processar a chamada da ferramenta
      choice["tool_calls"].each do |tool_call|
        function_name = tool_call.dig("function", "name")
        arguments = JSON.parse(tool_call.dig("function", "arguments"))
        
        result = execute_tool(function_name, arguments)
        
        # Reenviar para a IA com o resultado da ferramenta para formular a resposta final
        messages << { role: "assistant", content: nil, tool_calls: [tool_call] }
        messages << { role: "tool", tool_call_id: tool_call["id"], name: function_name, content: result.to_s }
      end
      
      # Segunda chamada para a IA gerar o texto final baseado no resultado das ferramentas
      second_response = @client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [{ role: "system", content: build_system_prompt }] + messages,
          temperature: @inbox.ai_temperature || 0.7
        }
      )
      
      return second_response.dig("choices", 0, "message", "content")
    else
      # Mensagem de texto normal
      return choice["content"]
    end
  end

  def execute_tool(name, args)
    account_id = @conversation.account_id
    contact = @conversation.contact

    case name
    when "search_properties"
      # Busca em Imóveis Avulsos (Properties)
      prop_query = Property.where(account_id: account_id)
      prop_query = prop_query.where("neighborhood ILIKE ?", "%#{args['neighborhood']}%") if args['neighborhood'].present?
      prop_query = prop_query.where("bedrooms >= ?", args['bedrooms']) if args['bedrooms'].present?
      prop_query = prop_query.where("price <= ?", args['max_price']) if args['max_price'].present?
      prop_results = prop_query.limit(3)

      # Busca em Condomínios (Condominia)
      condo_query = Condominium.where(account_id: account_id)
      condo_query = condo_query.where("neighborhood ILIKE ?", "%#{args['neighborhood']}%") if args['neighborhood'].present?
      condo_query = condo_query.where("min_price <= ?", args['max_price']) if args['max_price'].present?
      condo_results = condo_query.limit(3)
      
      if prop_results.empty? && condo_results.empty?
        "Nenhum imóvel encontrado com esses critérios."
      else
        response_texts = []
        if prop_results.any?
          response_texts << "Imóveis Avulsos:"
          response_texts += prop_results.map do |p|
            desc = "- ID #{p.id}: #{p.title || p.property_type || 'Imóvel'} em #{p.neighborhood}, #{p.city}. "
            desc += "Quartos: #{p.bedrooms || 0} (Suítes: #{p.suites || 0}). Banheiros: #{p.bathrooms || 0}. Vagas: #{p.parking_spots || 0}. "
            desc += "Área: #{p.built_area || p.total_area}m². "
            desc += "Preço: R$ #{p.price || 0}. Transação: #{p.listing_type}. "
            desc += "Descrição: #{p.description&.truncate(300) || 'Sem descrição.'}"
            desc
          end
        end
        
        if condo_results.any?
          response_texts << "Condomínios/Lançamentos:"
          response_texts += condo_results.map do |c|
            desc = "- ID #{c.id}: #{c.name} em #{c.neighborhood}, #{c.city}. "
            desc += "Preço: R$ #{c.min_price || 0} a R$ #{c.max_price || 0}. "
            desc += "Lazer: #{c.leisure_features&.truncate(150) || 'Não informado'}. "
            desc += "Estágio de Obra: #{c.construction_progress || 'Não informado'}. "
            desc
          end
        end
        
        response_texts.join("\n")
      end

    when "qualify_lead"
      contact.update!(
        temperature: args['temperature'],
        intention: args['intention']
      )
      "Lead qualificado com sucesso. Temperatura atualizada para #{args['temperature']} e intenção definida como: #{args['intention']}."

    when "create_appointment"
      Appointment.create!(
        account_id: account_id,
        contact_id: contact.id,
        property_id: args['property_id'],
        appointment_date: args['date'],
        start_time: args['time'],
        end_time: (Time.parse(args['time']) + 1.hour).strftime('%H:%M'),
        status: 'Agendado'
      )
      
      property = Property.find_by(id: args['property_id'], account_id: account_id)
      
      property_desc = "Visita Agendada"
      if property
        price_str = property.price ? "R$ #{property.price.to_i}" : ""
        bairro_str = property.neighborhood.present? ? " - #{property.neighborhood}" : ""
        property_desc = "Visita: #{property.title || property.property_type}#{bairro_str} #{price_str}".strip
      end
      
      contact.update!(
        status: 'visit',
        intention: property_desc
      )
      
      "Visita agendada com sucesso para #{args['date']} às #{args['time']} no imóvel ID #{args['property_id']}. O contato foi movido para 'Visita Agendada' no Kanban automaticamente."

    when "move_kanban_card"
      contact.update!(status: args['stage'])
      "O status do cliente foi atualizado para #{args['stage']} no CRM."
      
    when "send_property_photos"
      property = Property.find_by(id: args['property_id'], account_id: account_id)
      if property
        if property.photos.attached?
          # Envia as fotos em background para não travar a resposta principal da IA
          Thread.new do
            begin
              baileys_service = WhatsappBaileysService.new(@inbox)
              remote_jid = @conversation.contact.jid || @conversation.contact.phone
              
              property.photos.first(5).each_with_index do |photo, index|
                caption = index == 0 ? "Aqui estão as fotos do imóvel: #{property.title || property.property_type}" : ""
                
                # Envia via API do Baileys
                baileys_service.send_message(remote_jid, caption, photo)
                
                # Salva a mensagem no CRM e já anexa a imagem para que o WebSockets dispare com a foto
                begin
                  Message.create!(
                    account: @conversation.account,
                    conversation: @conversation,
                    text: caption.present? ? caption : "📎 Imagem enviada",
                    sender_type: 'User',
                    sender_id: nil,
                    source_id: "ai_photo_#{SecureRandom.hex(8)}",
                    status: :delivered,
                    attachment: photo.blob
                  )
                rescue => e
                  Rails.logger.error("Erro ao criar registro da mensagem com foto: #{e.message}")
                end
                
                sleep 2
              end
            rescue => e
              Rails.logger.error("Erro ao enviar fotos do imóvel: #{e.message}")
            end
          end
          "Fotos do imóvel enviadas com sucesso para o cliente."
        else
          "O imóvel não possui fotos cadastradas no sistema."
        end
      else
        "Imóvel não encontrado."
      end
      
    else
      "Erro: Ferramenta não implementada."
    end
  rescue => e
    "Erro ao executar a ferramenta: #{e.message}"
  end
end
