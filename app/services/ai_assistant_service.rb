require 'openai'

class AiAssistantService
  def initialize(inbox, conversation, extra_context: nil)
    @inbox = inbox
    @conversation = conversation
    @extra_context = extra_context
    api_key = GlobalSetting.fetch('openai_api_key').presence || ENV['OPENAI_API_KEY']
    @client = OpenAI::Client.new(access_token: api_key)
  end

  def self.transcribe_audio(media_data, filename, inbox)
    api_key = GlobalSetting.fetch('openai_api_key').presence || ENV['OPENAI_API_KEY']
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
    recent_messages = @conversation.messages.order(created_at: :asc).last(100)
    
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
    
    labels_instruction = "\n[ETIQUETAS]: Após concluir a ação principal da mensagem, use 'apply_label' para classificar o lead sempre que tiver certeza da situação: 'lead_quente' = interesse real e urgência; 'lead_frio' = só pesquisando; 'desqualificado' = fora do perfil. [OBRIGATÓRIO] Use 'com_atendente' SEMPRE que você disser ao cliente, de qualquer forma, que vai encaminhar/transferir/passar o atendimento para um corretor ou atendente humano — mesmo que essa instrução esteja em outra parte do seu prompt e não use essas palavras exatas (ex: 'vou te encaminhar para um corretor', 'o corretor vai confirmar os detalhes', 'vou passar para um especialista verificar'). Chame 'apply_label' com 'com_atendente' NA MESMA resposta em que disser isso ao cliente — nunca prometa a transferência sem chamar a ferramenta. Nunca interrompa outra ação apenas para etiquetar."
    routing_instruction = "\n[ROTEAMENTO DE DEPARTAMENTO]: Se o cliente mencionar assuntos que NÃO são de venda/locação de imóveis — como problemas no imóvel (vazamento, elétrica, infiltração), cobranças, boletos, contratos, segunda via de recibo — use imediatamente a ferramenta 'route_to_department' para encaminhar ao departamento correto: 'suporte' = problemas/manutenção no imóvel; 'financeiro' = cobranças, boletos, segunda via; 'manutencao' = reparos e serviços técnicos. Avise o cliente que está transferindo."

    prompt = "#{base_prompt}\nSeu nome é #{@inbox.ai_name || 'Assistente'}. Você atende clientes de uma imobiliária. Seja muito humana, empática e natural.\n[CONTEXTO TEMPORAL]: #{date_info} (Sempre use essa data e hora reais como base).\n[DADOS DO CLIENTE]: #{contact_info}#{labels_instruction}#{routing_instruction}"
    
    # Contexto extra injetado por integrações (portais, webhooks) — sem exigir config manual
    if @extra_context.present?
      prompt += "\n\n[CONTEXTO DA INTEGRAÇÃO]: #{@extra_context}"
    end

    status = @conversation.contact.status.presence || 'lead'

    case status
    when 'lead'
      prompt += "\n[FASE DE PRÉ-VENDA (SDR)]: Você está atuando como Recepcionista/SDR. O lead acabou de chegar. Seu ÚNICO objetivo é descobrir o que o cliente procura (bairro, valor, quartos) ou a urgência dele. NÃO ofereça proativamente agendar visitas nem empurre outros imóveis — apenas acolha, engaje e qualifique. EXCEÇÃO: se o cliente perguntar diretamente sobre um imóvel/condomínio específico (detalhes, preço, fotos), responda usando 'search_properties'/'send_property_photos' normalmente — isso não conta como 'vender', é só responder o que foi perguntado. Ao apresentar esses dados, nunca despeje a lista crua (ex: 'Segurança: X, Y, Z.') — escolha os destaques relevantes e conte de forma natural, como um bom corretor faria. Sempre que entender o que ele procura, use a ferramenta 'qualify_lead' para atualizar a intenção no CRM e avance o lead para 'visit' usando a ferramenta 'move_kanban_card'.\n[FOTOS]: Se o cliente pedir fotos, SEMPRE chame 'send_property_photos' primeiro (informe 'name' com o nome do imóvel/condomínio mencionado na conversa, mesmo sem saber o ID). Só diga que não há fotos se a ferramenta retornar essa informação — nunca negue de antemão."
    when 'visit', 'atendimento'
      prompt += "\n[FASE DE ATENDIMENTO/VENDAS]: Você está atuando como Corretora Digital. O lead já foi qualificado. Seu foco agora é usar a busca de imóveis ('search_properties'), apresentar opções de forma encantadora e agendar visitas ('create_appointment').\n[REGRAS DE APRESENTAÇÃO DE IMÓVEIS E CONDOMÍNIOS]: Quando apresentar um imóvel OU condomínio/lançamento, NUNCA despeje os dados crus em formato de lista robótica (ex: não copie 'Segurança: X, Y, Z. Lazer: A, B, C.' literalmente). Leia todas as informações retornadas (localização, diferenciais, segurança, lazer, social, serviços, infraestrutura, construtora, prazo de entrega etc.) e escolha os pontos mais relevantes para o que o cliente busca, contando de forma fluida, conversacional e vendedora, como um bom corretor faria — nunca cite todos os itens, apenas os destaques que fariam o cliente se interessar.\n[FOTOS]: Se o cliente pedir fotos, SEMPRE chame 'send_property_photos' primeiro (informe 'name' com o nome do imóvel/condomínio mencionado na conversa, mesmo sem saber o ID). Só diga que não há fotos se a ferramenta retornar essa informação — nunca negue de antemão."
    when 'proposal', 'won'
      prompt += "\n[FASE DE FECHAMENTO]: Você está atuando no pós-visita/negociação. Foque em tirar dúvidas documentais e financeiras. Não oferte novos imóveis para não desfocar a venda."
    else
      # Default fallback
      prompt += "\n[QUALIFICAÇÃO]: Sempre que entender o que o cliente procura, use a ferramenta 'qualify_lead'."
    end
    
    prompt
  end

  def defined_tools
    status = @conversation.contact.status.presence || 'lead'
    
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
        description: "Pesquisa imóveis e condomínios/lançamentos no banco de dados da imobiliária com base em critérios. Use 'name' sempre que o cliente mencionar um nome específico de condomínio/empreendimento/imóvel (ex: 'Di Cavalcanti').",
        parameters: {
          type: "object",
          properties: {
            name: { type: "string", description: "Nome do condomínio, empreendimento ou imóvel mencionado pelo cliente (busca parcial)." },
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
        description: "Agenda uma visita para o lead em um imóvel avulso OU condomínio/lançamento. Use o ID numérico retornado por search_properties (funciona para os dois tipos).",
        parameters: {
          type: "object",
          properties: {
            property_id: { type: "integer", description: "ID numérico do imóvel ou condomínio (retornado por search_properties como 'ID X:')" },
            date: { type: "string", description: "Data desejada no formato YYYY-MM-DD (ex: 2026-06-19)" },
            time: { type: "string", description: "Hora desejada no formato HH:MM (ex: 10:00). Sempre informe o horário combinado com o cliente." }
          },
          required: ["property_id", "date", "time"]
        }
      }
    }
    
    photos_tool = {
      type: "function",
      function: {
        name: "send_property_photos",
        description: "Envia as fotos de um imóvel ou condomínio para o cliente no WhatsApp. Se você não souber o ID, informe 'name' com o nome do imóvel/condomínio (ex: nome mencionado na conversa) que a busca é feita automaticamente. NUNCA diga que não tem fotos sem antes tentar esta ferramenta.",
        parameters: {
          type: "object",
          properties: {
            property_id: { type: "integer", description: "ID do imóvel ou condomínio, se já conhecido (retornado por search_properties)." },
            name: { type: "string", description: "Nome do imóvel ou condomínio, usado quando o ID não é conhecido." }
          }
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

    route_tool = {
      type: "function",
      function: {
        name: "route_to_department",
        description: "Encaminha a conversa para um agente do departamento correto (suporte, financeiro, manutencao). Use quando o assunto não é de venda/locação.",
        parameters: {
          type: "object",
          properties: {
            department: { type: "string", enum: ["suporte", "financeiro", "manutencao"], description: "Departamento de destino" },
            reason:     { type: "string", description: "Motivo do encaminhamento (ex: 'cliente relata vazamento')" }
          },
          required: ["department"]
        }
      }
    }

    label_tool = {
      type: "function",
      function: {
        name: "apply_label",
        description: "Aplica uma etiqueta na conversa para identificar a situação do lead. Use SEMPRE que identificar claramente a situação. Regras: 'lead_quente' = interesse real e urgência; 'lead_frio' = só pesquisando; 'desqualificado' = fora do perfil; 'com_atendente' = use quando o lead pede para falar com um humano ou a situação exige atendimento especializado (ex: negociação de proposta complexa, reclamação, solicitação explícita). Não use 'agente_off' — ela é aplicada automaticamente.",
        parameters: {
          type: "object",
          properties: {
            label: {
              type: "string",
              enum: ["lead_quente", "lead_frio", "desqualificado", "com_atendente"],
              description: "Etiqueta a aplicar na conversa."
            },
            reason: {
              type: "string",
              description: "Motivo breve pelo qual está aplicando esta etiqueta."
            }
          },
          required: ["label"]
        }
      }
    }

    case status
    when 'lead'
      [qualify_tool, search_tool, photos_tool, kanban_tool, label_tool, route_tool]
    when 'visit', 'atendimento'
      [search_tool, photos_tool, appointment_tool, kanban_tool, label_tool, route_tool]
    when 'proposal', 'won'
      [kanban_tool, label_tool, route_tool]
    else
      [qualify_tool, search_tool, photos_tool, appointment_tool, kanban_tool, label_tool, route_tool]
    end
  end

  def handle_response(response, messages)
    max_rounds = 4
    current_response = response

    max_rounds.times do
      choice = current_response.dig("choices", 0, "message")

      unless choice["tool_calls"]
        return choice["content"]
      end

      # Processa todos os tool_calls desta rodada
      all_tool_results = choice["tool_calls"].map do |tool_call|
        function_name = tool_call.dig("function", "name")
        arguments = JSON.parse(tool_call.dig("function", "arguments"))
        result = execute_tool(function_name, arguments)
        { tool_call: tool_call, name: function_name, result: result.to_s }
      end

      # Adiciona a chamada do assistente e todos os resultados ao histórico
      messages << { role: "assistant", content: nil, tool_calls: choice["tool_calls"] }
      all_tool_results.each do |tr|
        messages << { role: "tool", tool_call_id: tr[:tool_call]["id"], name: tr[:name], content: tr[:result] }
      end

      # Nova chamada com tools disponíveis (para permitir encadeamento)
      current_response = @client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [{ role: "system", content: build_system_prompt }] + messages,
          tools: defined_tools,
          tool_choice: "auto",
          temperature: @inbox.ai_temperature || 0.7
        }
      )
    end

    # Fallback: última resposta se atingiu o limite de rodadas
    current_response.dig("choices", 0, "message", "content")
  end

  def execute_tool(name, args)
    account_id = @conversation.account_id
    contact = @conversation.contact

    case name
    when "search_properties"
      # Busca em Imóveis Avulsos (Properties) — apenas disponíveis
      prop_query = Property.where(account_id: account_id, status: 'Disponível')
      prop_query = prop_query.where("neighborhood ILIKE ?", "%#{args['neighborhood']}%") if args['neighborhood'].present?
      prop_query = prop_query.where("bedrooms >= ?", args['bedrooms']) if args['bedrooms'].present?
      prop_query = prop_query.where("price <= ?", args['max_price']) if args['max_price'].present?
      prop_query = prop_query.where("title ILIKE :q OR condo_name ILIKE :q", q: "%#{args['name']}%") if args['name'].present?
      prop_results = prop_query.limit(3)
      prop_results.each { |p| p.increment!(:search_count) rescue nil }

      # Busca em Condomínios (Condominia) — exclui esgotados
      condo_query = Condominium.where(account_id: account_id).where.not(status: 'Esgotado')
      condo_query = condo_query.where("neighborhood ILIKE ?", "%#{args['neighborhood']}%") if args['neighborhood'].present?
      condo_query = condo_query.where("min_price <= ?", args['max_price']) if args['max_price'].present?
      condo_query = condo_query.where("name ILIKE ?", "%#{args['name']}%") if args['name'].present?
      condo_results = condo_query.limit(3)

      if prop_results.empty? && condo_results.empty?
        "Nenhum imóvel disponível encontrado com esses critérios."
      else
        response_texts = []
        if prop_results.any?
          response_texts << "Imóveis Avulsos:"
          response_texts += prop_results.map do |p|
            has_photos = p.photos.attached?
            desc = "- ID #{p.id}: #{p.title || p.property_type || 'Imóvel'} em #{p.neighborhood}, #{p.city}. "
            desc += "Status: #{p.status || 'Disponível'}. "
            desc += "Quartos: #{p.bedrooms || 0} (Suítes: #{p.suites || 0}). Banheiros: #{p.bathrooms || 0}. Vagas: #{p.parking_spots || 0}. "
            desc += "Área: #{p.built_area || p.total_area}m². "
            desc += "Preço: R$ #{p.price || 0}. Transação: #{p.listing_type}. "
            desc += "Descrição: #{p.description&.truncate(300) || 'Sem descrição.'}. "
            desc += has_photos ? "[TEM_FOTOS: SIM — você pode oferecer enviar fotos usando send_property_photos]" : "[TEM_FOTOS: NÃO — NÃO ofereça enviar fotos deste imóvel]"
            desc
          end
        end

        if condo_results.any?
          response_texts << "Condomínios/Lançamentos:"
          response_texts += condo_results.map do |c|
            has_photos = c.photos.attached?
            desc = "- ID #{c.id}: #{c.name}, em #{c.neighborhood}, #{c.city}/#{c.state}. "
            desc += "Endereço: #{c.street}, #{c.number}. " if c.street.present?
            desc += "Status comercial: #{c.status || 'Disponível'}. "
            desc += "Progresso da obra: #{c.construction_progress}. " if c.construction_progress.present?
            desc += "Entrega prevista: #{c.delivery_date.strftime('%m/%Y')}. " if c.delivery_date.present?
            desc += "Preço: R$ #{c.min_price || 0} a R$ #{c.max_price || 0}. "
            desc += "Construtora: #{c.builder}. " if c.builder.present?
            desc += "Incorporadora: #{c.developer}. " if c.developer.present?
            desc += "Tipo: #{c.condominium_types}. " if c.condominium_types.present?
            desc += "Área do terreno: #{c.land_area}m². " if c.land_area.present?
            desc += "Área construída: #{c.built_area}m². " if c.built_area.present?
            desc += "Diferenciais: #{c.tags}. " if c.tags.present?
            desc += "Segurança: #{c.security_features.truncate(200)}. " if c.security_features.present?
            desc += "Lazer: #{c.leisure_features.truncate(300)}. " if c.leisure_features.present?
            desc += "Social: #{c.social_features.truncate(200)}. " if c.social_features.present?
            desc += "Serviços: #{c.services.truncate(200)}. " if c.services.present?
            desc += "Infraestrutura: #{c.infrastructure.truncate(200)}. " if c.infrastructure.present?
            desc += has_photos ? "[TEM_FOTOS: SIM — você pode oferecer enviar fotos usando send_property_photos]" : "[TEM_FOTOS: NÃO — NÃO ofereça enviar fotos deste condomínio]"
            desc
          end
        end

        response_texts.join("\n")
      end

    when "create_appointment"
      visit_time = args['time'].presence || '10:00'
      end_time_str = begin
        (Time.parse(visit_time) + 1.hour).strftime('%H:%M')
      rescue
        '11:00'
      end

      listing_id = args['property_id']
      property = Property.find_by(id: listing_id, account_id: account_id)
      condo = property.nil? ? Condominium.find_by(id: listing_id, account_id: account_id) : nil

      Appointment.create!(
        account_id: account_id,
        contact_id: contact.id,
        property_id: property&.id,
        condominium_id: condo&.id,
        user_id: @conversation.user_id,
        appointment_date: args['date'],
        start_time: visit_time,
        end_time: end_time_str,
        status: 'Agendado'
      )

      listing = property || condo
      property_desc = "Visita Agendada"
      if listing
        name = listing.try(:title) || listing.try(:name) || listing.try(:property_type)
        price_val = listing.try(:price) || listing.try(:min_price)
        price_str = price_val ? "R$ #{price_val.to_i}" : ""
        bairro_str = listing.neighborhood.present? ? " - #{listing.neighborhood}" : ""
        property_desc = "Visita: #{name}#{bairro_str} #{price_str}".strip
      end

      contact.update!(
        status: 'visit',
        intention: property_desc
      )

      execute_tool('apply_label', { 'label' => 'visita_agendada', 'reason' => 'Visita agendada pela IA' })

      "Visita agendada com sucesso para #{args['date']} às #{args['time']} no imóvel ID #{args['property_id']}. O contato foi movido para 'Visita Agendada' no Kanban automaticamente."

    when "apply_label"
      label_name = args['label'].to_s.strip.downcase
      colors = { 'lead_quente' => '#ef4444', 'lead_frio' => '#3b82f6', 'desqualificado' => '#6b7280', 'com_atendente' => '#8b5cf6', 'visita_agendada' => '#10b981' }
      color = colors[label_name] || '#6b7280'

      # Remove etiquetas conflitantes antes de aplicar
      conflicting = { 'lead_quente' => ['lead_frio'], 'lead_frio' => ['lead_quente'], 'desqualificado' => ['lead_quente', 'lead_frio'] }
      (conflicting[label_name] || []).each do |remove_name|
        old_tag = @conversation.account.tags.find_by(name: remove_name)
        @conversation.tags.delete(old_tag) if old_tag && @conversation.tags.include?(old_tag)
      end

      tag = @conversation.account.tags.find_or_create_by!(name: label_name) { |t| t.color = color }
      @conversation.tags << tag unless @conversation.tags.include?(tag)

      ActionCable.server.broadcast("conversations_channel_#{@conversation.account_id}", {
        event: 'conversation_tags_updated',
        conversation_id: @conversation.id,
        tags: @conversation.reload.tags.map { |t| { id: t.id, name: t.name, color: t.color } }
      })

      # Pausa IA permanentemente para labels que encerram o ciclo de IA
      if %w[com_atendente visita_agendada desqualificado].include?(label_name)
        pause_ai_permanently
        # Atribui para o próximo da fila em qualquer encerramento de ciclo (exceto desqualificado)
        if %w[com_atendente visita_agendada].include?(label_name)
          RoundRobinAssignmentService.assign_next(@conversation.reload)
        end
      end

      "Etiqueta '#{label_name}' aplicada na conversa. #{args['reason']}"

    when "qualify_lead"
      contact.update!(temperature: args['temperature'], intention: args['intention'])

      # Auto-aplica etiqueta correspondente à temperatura
      temp_label_map = { 'Quente' => 'lead_quente', 'Frio' => 'lead_frio', 'Morno' => 'lead_morno' }
      label_name = temp_label_map[args['temperature']]
      label_colors = { 'lead_quente' => '#ef4444', 'lead_frio' => '#3b82f6', 'lead_morno' => '#f59e0b' }

      if label_name
        # Remove etiquetas de temperatura anteriores
        ['lead_quente', 'lead_frio', 'lead_morno'].each do |n|
          t = @conversation.account.tags.find_by(name: n)
          next unless t
          ct = @conversation.conversation_tags.find_by(tag_id: t.id)
          ct&.delete
        end
        @conversation.tags.reset

        tag = @conversation.account.tags.find_or_create_by!(name: label_name) { |t| t.color = label_colors[label_name] }
        @conversation.tags << tag

        ActionCable.server.broadcast("conversations_channel_#{@conversation.account_id}", {
          event: 'conversation_tags_updated',
          conversation_id: @conversation.id,
          tags: @conversation.reload.tags.map { |t| { id: t.id, name: t.name, color: t.color } }
        })
      end

      "Lead qualificado: temperatura=#{args['temperature']}, intenção=#{args['intention']}."

    when "route_to_department"
      dept = args['department'].to_s
      agent = User.where(account_id: account_id, status: 'active', department: dept)
                  .order(Arel.sql('queue_position ASC NULLS FIRST, id ASC'))
                  .first

      if agent
        @conversation.update!(user_id: agent.id)
        ActionCable.server.broadcast("conversations_channel_#{@conversation.account_id}", {
          event: 'lead_atribuido',
          assigned_to_user_id: agent.id,
          conversation_id: @conversation.id,
          contact_name: contact.name.presence || contact.phone,
          assigned_by: 'ia_routing'
        })
        AgentNotificationService.notify_assignment(
          agent: agent, conversation: @conversation, assigned_by: 'ia'
        ) rescue nil
        pause_ai_permanently
        dept_label = { 'suporte' => 'Suporte', 'financeiro' => 'Financeiro', 'manutencao' => 'Manutenção' }[dept] || dept
        "Conversa encaminhada para #{agent.first_name} (#{dept_label}). IA pausada."
      else
        "Nenhum agente disponível no departamento #{dept} no momento."
      end

    when "move_kanban_card"
      contact.update!(status: args['stage'])
      "O status do cliente foi atualizado para #{args['stage']} no CRM."
      
    when "send_property_photos"
      property = nil
      if args['property_id'].present?
        property = Property.find_by(id: args['property_id'], account_id: account_id) ||
                   Condominium.find_by(id: args['property_id'], account_id: account_id)
      end
      if property.nil? && args['name'].present?
        property = Property.where(account_id: account_id).where("title ILIKE :q OR condo_name ILIKE :q", q: "%#{args['name']}%").first ||
                   Condominium.where(account_id: account_id).where("name ILIKE ?", "%#{args['name']}%").first
      end
      if property.nil?
        # Fallback: nome pode não bater por variação de grafia (ex: "Cavalcanti" vs "Cavalcante")
        # ou o cliente pode ter perguntado sem repetir o nome ("Tem foto?"). Se a conta só
        # vende UM condomínio, não há ambiguidade em assumir esse, mesmo havendo imóveis avulsos.
        active_condos = Condominium.where(account_id: account_id).where.not(status: 'Esgotado')
        property = active_condos.first if active_condos.count == 1
      end
      if property
        if property.photos.attached?
          # Envia as fotos em background para não travar a resposta principal da IA
          Thread.new do
            begin
              baileys_service = WhatsappBaileysService.new(@inbox)
              remote_jid = @conversation.contact.jid || @conversation.contact.phone
              
              property.photos.first(5).each_with_index do |photo, index|
                label = property.try(:title) || property.try(:name) || property.try(:property_type) || 'imóvel'
                caption = index == 0 ? "Aqui estão as fotos: #{label}" : ""
                
                # Envia via API do Baileys
                baileys_id = baileys_service.send_message(remote_jid, caption, photo)

                # Salva a mensagem no CRM e já anexa a imagem para que o WebSockets dispare com a foto
                begin
                  Message.create!(
                    account: @conversation.account,
                    conversation: @conversation,
                    text: caption.present? ? caption : "📎 Imagem enviada",
                    sender_type: 'User',
                    sender_id: nil,
                    source_id: baileys_id.presence || "ai_photo_#{SecureRandom.hex(8)}",
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

  def pause_ai_permanently
    jid = @conversation.contact.jid.presence || @conversation.contact.phone
    return unless jid

    # Pausa sem expiração — só é retomada pelo botão "Retomar IA"
    Rails.cache.write("ai_paused_#{@inbox.id}_#{jid}", Time.current.to_i)

    # Aplica tag agente_off para indicar visualmente que a IA está desligada
    tag = @conversation.account.tags.find_or_create_by!(name: 'agente_off') { |t| t.color = '#f97316' }
    @conversation.tags << tag unless @conversation.tags.include?(tag)

    ActionCable.server.broadcast("conversations_channel_#{@conversation.account_id}", {
      event: 'conversation_tags_updated',
      conversation_id: @conversation.id,
      tags: @conversation.reload.tags.map { |t| { id: t.id, name: t.name, color: t.color } }
    })
  rescue => e
    Rails.logger.error("Erro ao pausar IA: #{e.message}")
  end
end
