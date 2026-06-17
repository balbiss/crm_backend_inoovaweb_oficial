# Realiza Vale CRM — Documentação Completa

## Visão Geral

O **Realiza Vale** é um CRM SaaS para imobiliárias com atendimento via WhatsApp, IA integrada (GPT-4o), funil de vendas (Kanban), cadastro de imóveis, agendamento de visitas e rodízio automático de atendentes.

---

## Stack Tecnológica

| Camada | Tecnologia |
|---|---|
| Backend | Ruby on Rails 8 (API mode) |
| Frontend | Vue.js 3 + Vite + Pinia |
| Banco de dados | PostgreSQL |
| WhatsApp | Baileys API (container próprio, porta 3025) |
| IA | OpenAI GPT-4o + GPT-4o-mini + Whisper |
| Autenticação | Devise + JWT |
| WebSocket | ActionCable |
| Storage | ActiveStorage (disco local) |
| Pagamentos | Stripe |
| Deploy | Docker Compose |

---

## Arquitetura

```
Browser (Vue.js :5173)
     │
     ├── REST API  ──────────────▶  Rails :3000
     │                                  │
     └── WebSocket (ActionCable) ◀──────┤
                                        │
                                   PostgreSQL
                                        │
                          Baileys API :3025 ──▶ WhatsApp
```

**Containers Docker:**
- `crm-backend-web-1` — Rails (porta 3000)
- `crm-backend-baileys-api-1` — Baileys/WhatsApp (porta 3025)
- `crm-backend-db-1` — PostgreSQL

---

## Módulos e Funcionalidades

---

### 1. Autenticação e Usuários (`/agents`, Devise + JWT)

**Papéis (`role`):**
| Role | Descrição |
|---|---|
| `empresa` | Dono da imobiliária — acesso total |
| `admin` | Administrador — acesso total |
| `atendente` | Corretor padrão — acesso restrito |

**Funcionalidades:**
- Registro, login, logout com token JWT
- Recuperação de senha por e-mail
- Bloqueio/desbloqueio de acesso por conta (`status: blocked/active`)
- Permissões customizadas por JSON (`permissions: { view_all_contacts: true, ... }`)
- **Rodízio automático** — campo `available_for_roundrobin` e `queue_position`

**Endpoints:**
```
GET    /agents               — lista todos os agentes da conta
POST   /agents               — cria novo agente (role: atendente por padrão)
PUT    /agents/:id           — edita agente
PATCH  /agents/:id/block     — bloqueia acesso
PATCH  /agents/:id/unblock   — desbloqueia acesso
PATCH  /agents/:id/toggle_roundrobin — ativa/desativa na fila de rodízio
GET    /agents/queue         — lista ordem atual da fila de rodízio
DELETE /agents/:id           — remove agente
```

---

### 2. Inbox (Conexão WhatsApp)

O **Inbox** representa uma conexão WhatsApp. A imobiliária pode ter múltiplos inboxes (múltiplos números).

**Campos principais:**
| Campo | Função |
|---|---|
| `name` | Nome do inbox |
| `provider` | Sempre `baileys` |
| `phone_number` | Número conectado |
| `ai_enabled` | Liga/desliga IA para este inbox |
| `ai_name` | Nome da IA (ex: "Lara") |
| `ai_prompt` | Prompt base de comportamento |
| `ai_temperature` | Criatividade da IA (0.0–1.0) |
| `working_hours_enabled` | Ativa controle de horário |
| `working_hours` | JSON com dias/horários de atendimento |
| `out_of_office_message` | Mensagem fora do horário |
| `followup_enabled` | Ativa follow-up automático |
| `followup_max_attempts` | Quantas tentativas de follow-up |
| `followup_wait_time_minutes` | Intervalo entre follow-ups |

**Fluxo de conexão:**
1. Imobiliária cria um inbox → sistema registra na Baileys API
2. Frontend busca QR Code via `GET /inboxes/:id/qr_code`
3. Usuário escaneia QR com WhatsApp → inbox conectado
4. Mensagens passam a chegar via webhook `POST /webhooks/baileys`

**Endpoints:**
```
GET    /inboxes              — lista inboxes
POST   /inboxes              — cria inbox e registra no Baileys
PUT    /inboxes/:id          — atualiza configurações
GET    /inboxes/:id/qr_code  — retorna QR code para escanear
GET    /inboxes/:id/status   — verifica se está conectado
POST   /inboxes/:id/generate_prompt — gera prompt via GPT-4o
DELETE /inboxes/:id          — remove inbox e desconecta do Baileys
```

---

### 3. Webhook Baileys — Motor Central

Arquivo: `app/controllers/webhooks/baileys_controller.rb`

Todo evento do WhatsApp chega aqui. O controller processa:

#### 3.1 Mensagens Recebidas (do cliente)
1. Identifica o inbox pelo header `X-API-Key`
2. Busca ou cria contato pelo JID (`@s.whatsapp.net` ou `@lid`)
3. Busca ou cria conversa (Conversation)
4. Salva a mensagem (texto, imagem, áudio, vídeo, documento)
5. **Transcreve áudios** via Whisper (OpenAI) automaticamente
6. Emite evento WebSocket `message_created` para o frontend
7. Verifica se IA está ativa e se deve responder (veja seção IA)

#### 3.2 Mensagens Enviadas pelo Humano (fromMe)
1. Detecta mensagem enviada pelo atendente humano
2. Pausa a IA **permanentemente** para aquele contato
3. Aplica etiqueta `agente_off` na conversa
4. Emite WebSocket `conversation_tags_updated`

#### 3.3 Atualizações de Status de Conexão
- Salva status (`open`, `connecting`, `close`) no cache
- Salva QR Code no cache quando disponível

---

### 4. Motor de IA (`AiAssistantService`)

Arquivo: `app/services/ai_assistant_service.rb`

#### Como a IA é ativada

Antes de chamar a IA, o sistema verifica:
1. `inbox.ai_enabled` — IA ligada para este inbox?
2. `Rails.cache.read("ai_paused_#{inbox_id}_#{jid}")` — IA não está pausada?
3. `conversation.status == 'open'` — conversa aberta?
4. Horário de atendimento (se `working_hours_enabled`)

**Debounce de 8 segundos:** se o cliente enviar várias mensagens seguidas, o sistema aguarda 8 segundos antes de processar, agrupando todas as mensagens.

#### System Prompt dinâmico

O prompt varia conforme o **estágio do contato (`status`)**:

| Status | Papel da IA |
|---|---|
| `lead` | SDR — qualifica, não oferta imóveis |
| `visit` / `atendimento` | Corretora — busca imóveis, agenda visitas |
| `proposal` / `won` | Pós-venda — tira dúvidas documentais |

O prompt inclui sempre:
- Data/hora atual em PT-BR
- Nome e telefone do contato
- Instruções de etiquetas

#### Ferramentas (Function Calling GPT-4o)

| Ferramenta | Quando disponível | O que faz |
|---|---|---|
| `qualify_lead` | fase `lead` | Atualiza temperatura (Frio/Morno/Quente) e intenção do lead no CRM |
| `move_kanban_card` | todas | Move o lead no funil (lead → visit → proposal → won) |
| `apply_label` | todas | Aplica etiqueta na conversa |
| `search_properties` | fase `visit` | Busca imóveis no banco por bairro, quartos, preço máximo |
| `send_property_photos` | fase `visit` | Envia fotos do imóvel via WhatsApp |
| `create_appointment` | fase `visit` | Agenda visita e move lead para fase `visit` no Kanban |

#### Multi-round tool calling

A IA pode encadear até 4 rounds de ferramentas por mensagem. Exemplo real:
1. Cliente pede imóvel → IA chama `search_properties`
2. IA apresenta imóvel, cliente confirma → IA chama `create_appointment` + `apply_label('visita_agendada')`
3. `apply_label('visita_agendada')` aciona `pause_ai_permanently` automaticamente

#### Pausa da IA

A IA pausa **permanentemente** (sem expiração) quando:
- Atendente humano envia mensagem (fromMe)
- IA aplica label `com_atendente`
- IA aplica label `visita_agendada`
- IA aplica label `desqualificado`

A IA é **retomada** manualmente pelo atendente clicando em "Retomar IA" na interface.

#### Divisão de mensagens

A IA divide respostas longas em múltiplas mensagens menores (simulando digitação humana) via `split_into_messages` usando GPT-4o-mini.

#### Geração de Resumo

`POST /conversations/:id/generate_summary` — Gera resumo do atendimento (últimas 30 mensagens) via GPT-4o-mini.

---

### 5. Etiquetas (Tags)

**Etiquetas automáticas aplicadas pela IA:**

| Etiqueta | Cor | Quando |
|---|---|---|
| `lead_quente` | Vermelho `#ef4444` | Lead com interesse real e urgência |
| `lead_frio` | Azul `#3b82f6` | Lead só pesquisando |
| `lead_morno` | Amarelo `#f59e0b` | Lead interessado mas sem urgência |
| `desqualificado` | Cinza `#6b7280` | Fora do perfil da imobiliária |
| `com_atendente` | Roxo `#8b5cf6` | Transferido para humano |
| `visita_agendada` | Verde `#10b981` | Visita agendada pelo sistema |

**Etiquetas automáticas aplicadas pelo sistema:**

| Etiqueta | Cor | Quando |
|---|---|---|
| `agente_off` | Laranja `#f97316` | Sempre que humano assume ou IA pausa |

**Etiquetas customizadas:** criadas manualmente pelo usuário em `Configurações > Etiquetas`.

**Endpoints:**
```
GET    /conversations/:id/tags    — lista etiquetas da conversa
POST   /conversations/:id/tags    — adiciona etiqueta
DELETE /conversations/:id/tags/:id — remove etiqueta
GET    /tags                      — lista etiquetas da conta
POST   /tags                      — cria etiqueta
```

---

### 6. Conversas (`ConversationsController`)

**Campos principais:**
| Campo | Descrição |
|---|---|
| `status` | `open`, `pending`, `resolved`, `snoozed` |
| `user_id` | Atendente responsável |
| `unread_count` | Mensagens não lidas |
| `inbox_id` | Inbox de origem |

**Endpoints:**
```
GET  /conversations           — lista todas as conversas da conta
GET  /conversations/:id       — detalhes + mensagens
PUT  /conversations/:id       — atualiza status ou atribui atendente
GET  /conversations/:id/ai_status  — verifica se IA está pausada
POST /conversations/:id/resume_ai  — retoma a IA (remove agente_off)
POST /conversations/:id/generate_summary — gera resumo com IA
```

**Atribuição de atendente:**
- Ao alterar `user_id` via `PUT /conversations/:id`, o sistema automaticamente aplica/remove a etiqueta `com_atendente`
- Quando `user_id` é definido → adiciona `com_atendente`
- Quando `user_id` é removido → remove `com_atendente`

**WebSocket — eventos em tempo real:**

| Evento | Quando disparado |
|---|---|
| `message_created` | Nova mensagem chega ou IA responde |
| `conversation_tags_updated` | Etiquetas da conversa mudam |
| `conversation_updated` | Status, atendente ou qualquer campo muda |
| `contact_updated` | Dados do contato são alterados |
| `inbox_updated` | Configurações do inbox mudam |

---

### 7. Rodízio Automático de Atendentes (`RoundRobinAssignmentService`)

Arquivo: `app/services/round_robin_assignment_service.rb`

#### Como funciona

1. Cada agente tem `available_for_roundrobin` (boolean) e `queue_position` (integer)
2. Quando a IA aplica `com_atendente`, o sistema chama `RoundRobinAssignmentService.assign_next`
3. O agente com **menor `queue_position`** é selecionado (NULLS FIRST para novos)
4. O agente selecionado recebe a conversa (`conversation.user_id = agent.id`)
5. O agente vai para o **final da fila** (`queue_position = MAX + 1`)
6. Broadcast WebSocket notifica o frontend da atribuição

#### Proteção contra duplicação
- `ApplicationRecord.transaction` com `lock!` garante que dois leads simultâneos nunca vão para o mesmo agente
- Se `conversation.user_id` já está definido, o rodízio não executa

#### Gerenciamento da fila (via frontend `/agentes`)
- Toggle por agente para entrar/sair da fila
- Ao ativar: entra no final da fila
- Ao desativar: sai da fila (`queue_position = nil`)
- Painel visual mostra ordem atual com indicador "próximo"

---

### 8. Contatos

**Campos do contato:**
| Campo | Descrição |
|---|---|
| `name` | Nome completo |
| `phone` | Telefone |
| `jid` | JID do WhatsApp (`@s.whatsapp.net` ou `@lid`) |
| `email` | E-mail |
| `temperature` | Frio / Morno / Quente (atualizado pela IA) |
| `status` | Estágio no Kanban: `lead`, `visit`, `proposal`, `won` |
| `intention` | O que busca (atualizado pela IA) |
| `source` | Origem (WhatsApp, site, indicação...) |
| `cpf`, `birth_date`, `profession` | Dados pessoais |
| `gross_income`, `down_payment`, `fgts_balance` | Dados financeiros |
| `cep`, `street`, `neighborhood`, `city`, `state` | Endereço |

**Endpoints:**
```
GET    /contacts          — lista contatos (dono/admin: todos; corretor: apenas os seus)
GET    /contacts/:id      — detalhes + conversas + notas
POST   /contacts          — cria contato
PUT    /contacts/:id      — atualiza dados
DELETE /contacts/:id      — remove contato
POST   /contacts/:id/merge — mescla com outro contato
POST   /contacts/:id/add_note — adiciona nota ao contato
```

---

### 9. Imóveis (`PropertiesController`)

**Campos principais:**
| Campo | Descrição |
|---|---|
| `title` | Título do anúncio |
| `property_type` | Tipo: Apartamento, Casa, Terreno... |
| `listing_type` | Venda ou Aluguel |
| `price` | Valor em reais |
| `status` | Disponível, Vendido, Reservado... |
| `bedrooms`, `suites`, `bathrooms`, `parking_spots` | Estrutura |
| `built_area`, `total_area` | Áreas |
| `neighborhood`, `city`, `state` | Localização |
| `latitude`, `longitude` | Coordenadas GPS |
| `photos` | Fotos via ActiveStorage (`has_many_attached`) |

**Busca pela IA** (`search_properties`):
- Filtra por `neighborhood`, `bedrooms`, `max_price`
- Retorna até 5 imóveis disponíveis
- Indica `[TEM_FOTOS: SIM/NÃO]` para que a IA saiba se pode oferecer envio de fotos

**Endpoints:**
```
GET    /properties        — lista imóveis
GET    /properties/:id    — detalhes + URLs das fotos
POST   /properties        — cria imóvel (suporta upload de fotos)
PUT    /properties/:id    — edita imóvel (pode remover fotos individuais)
DELETE /properties/:id    — remove imóvel
```

---

### 10. Condomínios (`CondominiumsController`)

Cadastro de condomínios vinculados aos imóveis. Campos incluem nome, endereço, lazer, infraestrutura e fotos.

---

### 11. Agendamentos (`AppointmentsController`)

Representa visitas de clientes a imóveis.

**Campos:**
| Campo | Descrição |
|---|---|
| `contact_id` | Lead visitante |
| `property_id` | Imóvel a visitar |
| `appointment_date` | Data da visita |
| `start_time`, `end_time` | Horário |
| `broker_name` | Nome do corretor responsável |
| `status` | scheduled, completed, cancelled |

**Criação automática pela IA:** quando o cliente confirma interesse em visitar e a IA chama `create_appointment`, o sistema:
1. Cria o Appointment no banco
2. Move o lead para `visit` no Kanban
3. Aplica etiqueta `visita_agendada`
4. Pausa a IA permanentemente

**Endpoints:**
```
GET    /appointments      — lista agendamentos
GET    /appointments/:id  — detalhes
POST   /appointments      — cria agendamento
PUT    /appointments/:id  — edita
DELETE /appointments/:id  — cancela
```

---

### 12. Funil de Vendas — Kanban

A página **Funil de Vendas** exibe os contatos em colunas baseadas no campo `contact.status`:

| Coluna | Status | Movido por |
|---|---|---|
| Novos Leads | `lead` | Chegada automática via WhatsApp |
| Atendimento | `atendimento` | — |
| Visita Agendada | `visit` | IA (`create_appointment`) ou manual |
| Proposta Feita | `proposal` | IA (`move_kanban_card`) ou manual |
| Negócio Fechado | `won` | IA ou manual |

A IA move o card automaticamente via ferramenta `move_kanban_card`.

---

### 13. Dashboard

`GET /dashboard` retorna KPIs:
- Total de contatos ativos
- Contatos com intenção de venda
- Temperatura dos leads (Quente / Morno / Frio)
- Leads por fonte (WhatsApp, site, etc.)

---

### 14. Mensagens Agendadas (`ScheduledMessagesController`)

Mensagens programadas para serem enviadas em data/hora específica via WhatsApp.

```
GET    /conversations/:id/scheduled_messages
POST   /conversations/:id/scheduled_messages
DELETE /conversations/:id/scheduled_messages/:id
```

---

### 15. Notificações (`NotificationsController`)

```
GET /notifications            — lista notificações do usuário
PUT /notifications/mark_all_read
PUT /notifications/:id/mark_as_read
```

---

### 16. Configurações da Conta (`AccountsController`)

```
GET /account         — dados da conta
PUT /account         — atualiza nome, logo, etc.
PUT /account/update_password — altera senha
```

---

### 17. Gerador de Prompt (`POST /inboxes/:id/generate_prompt`)

Gera automaticamente o `ai_prompt` da IA via GPT-4o com base nos dados informados:

| Parâmetro | Descrição |
|---|---|
| `identity` | Identidade e tom de voz da IA |
| `institutional` | Horários, diferenciais da imobiliária |
| `faq` | Perguntas e respostas frequentes |
| `sdr_rules` | Dados obrigatórios de qualificação |
| `routing_rules` | Quando transferir para humano |
| `ai_role` | `sdr_only` ou `full` (SDR + Corretora) |
| `allow_scheduling` | Permite agendamento automático? |
| `use_whatsapp_name` | Usa nome do contato do WhatsApp? |
| `emoji_usage` | `none`, `moderate`, `lots` |
| `prohibited_actions` | O que a IA não pode fazer |

---

### 18. Suporte (`SupportTicketsController`)

Sistema interno de suporte com tickets e mensagens em chat.

```
GET  /support_tickets
POST /support_tickets
GET  /support_tickets/:id
POST /support_tickets/:id/support_ticket_messages
```

---

### 19. Painel Admin

Acessível apenas para usuários com role `admin` global.

| Rota | Função |
|---|---|
| `GET /admin/dashboard` | KPIs globais de todas as contas |
| `GET /admin/accounts` | Lista todas as empresas cadastradas |
| `POST /admin/accounts` | Cria nova empresa |
| `PUT /admin/accounts/:id` | Edita empresa |
| `PUT /admin/accounts/:id/block` | Bloqueia acesso da empresa |
| `GET /admin/support_tickets` | Todos os tickets de suporte |

---

### 20. Faturamento (`BillingController` — Stripe)

```
POST /billing/checkout  — cria sessão de checkout Stripe
POST /billing/portal    — abre portal de gerenciamento de assinatura
```

O webhook Stripe (`POST /webhooks/stripe`) processa eventos de pagamento e atualiza o acesso da conta.

---

## Fluxo Completo — Lead Chegando pelo WhatsApp

```
1. Cliente envia mensagem no WhatsApp
           ↓
2. Baileys API recebe e dispara webhook POST /webhooks/baileys
           ↓
3. Sistema identifica inbox pelo API Key
4. Busca/cria Contact pelo JID do WhatsApp
5. Busca/cria Conversation para aquele contato
6. Salva Message no banco
7. Emite WebSocket → frontend atualiza em tempo real
           ↓
8. Verifica: IA ativa? IA não pausada? Conversa aberta? Horário de atendimento?
           ↓ (se tudo OK)
9. Debounce 8 segundos (aguarda mensagens seguidas)
           ↓
10. AiAssistantService.new(inbox, conversation).process
    - Monta histórico de mensagens
    - Monta system prompt (baseado no estágio do lead)
    - Chama GPT-4o com function calling
           ↓
11. GPT-4o pode chamar ferramentas:
    - qualify_lead → atualiza temperatura + intenção
    - search_properties → busca imóveis no banco
    - create_appointment → agenda visita
    - apply_label → etiqueta a conversa
    - move_kanban_card → avança no funil
    - send_property_photos → envia fotos
           ↓
12. IA gera resposta final
13. split_into_messages → divide em múltiplas mensagens naturais
14. Cada mensagem enviada via Baileys API + salva no banco
15. WebSocket → frontend mostra as respostas em tempo real
           ↓
16. Se visita agendada / desqualificado / com_atendente:
    → pause_ai_permanently() → IA pausa, agente_off aplicado
    → Se com_atendente: RoundRobinAssignmentService.assign_next()
       → próximo atendente da fila recebe a conversa
       → vai para o final da fila
```

---

## Permissões por Role

| Funcionalidade | `atendente` | `empresa` / `admin` |
|---|---|---|
| Ver todas as conversas | ✓ | ✓ |
| Ver todos os contatos | ✗ (só os seus) | ✓ |
| Ver todos os imóveis | ✗ (só os seus) | ✓ |
| Ver todos os agendamentos | ✗ (só os seus) | ✓ |
| Criar/editar inbox | ✗ | ✓ |
| Criar/bloquear agentes | ✗ | ✓ |
| Painel Admin | ✗ | ✓ (role admin global) |

---

## Índices de Performance no Banco

```sql
contacts(jid)                           -- busca por JID em todo webhook
contacts(account_id, jid)               -- busca de contato dentro de conta
contacts(account_id, status)            -- filtro Kanban
messages(conversation_id, created_at)   -- ordenação de mensagens
conversations(account_id, status)       -- filtro de conversas
conversations(last_activity_at)         -- ordenação por recência
conversation_tags(conversation_id, tag_id) [UNIQUE] -- evita tags duplicadas
users(account_id, available_for_roundrobin, queue_position) -- fila de rodízio
```

---

## Variáveis de Ambiente

| Variável | Uso |
|---|---|
| `OPENAI_API_KEY` | Chave da OpenAI (ou salva em `global_settings`) |
| `API_HOST` | Host da API Rails (ex: `http://localhost:3000`) |
| `DATABASE_URL` | Conexão PostgreSQL |
| `RAILS_MASTER_KEY` | Chave de credentials do Rails |
| `STRIPE_SECRET_KEY` | Chave secreta do Stripe |
| `STRIPE_WEBHOOK_SECRET` | Segredo do webhook Stripe |

---

## Arquivos-Chave

| Arquivo | Responsabilidade |
|---|---|
| `app/services/ai_assistant_service.rb` | Motor de IA — toda lógica de GPT-4o, ferramentas, respostas |
| `app/controllers/webhooks/baileys_controller.rb` | Recebe todos os eventos do WhatsApp |
| `app/services/round_robin_assignment_service.rb` | Rodízio de atendentes |
| `app/services/whatsapp_baileys_service.rb` | Client HTTP para a Baileys API |
| `app/models/property.rb` | Imóveis + fotos (ActiveStorage) |
| `app/channels/conversations_channel.rb` | WebSocket em tempo real |
| `config/routes.rb` | Todas as rotas da API |
| `db/migrate/` | Histórico completo do banco de dados |
