# CRM VisitaIA — Backend (Rails 8)

## Visão Geral
CRM SaaS para imobiliárias. Produto do usuário Guilherme Balbis (balbis2050@gmail.com).
URL de produção: `crmchat.visitaia.com.br`
Deploy via: Docker Swarm + Portainer

## Stack Backend
- Ruby on Rails 8 (API mode)
- PostgreSQL
- Devise + Devise-JWT (autenticação)
- ActionCable (WebSocket para chat em tempo real)
- Sidekiq + Redis (background jobs)
- OpenAI GPT-4o-mini (matching lead ↔ imóvel, resumo de conversa)
- Asaas (cobrança/billing)
- VAPID (push notifications)

## Modelos Principais
- `User` — roles: atendente(0), empresa(1), admin(2). Campo `status` ('active'/'blocked'). `permissions` JSON.
- `Account` — tenant/empresa cliente do SaaS
- `Contact` — lead/cliente. Campos: name, phone, email, temperature, source, intention (texto para matching)
- `Conversation` — conversa de WhatsApp. status: open/resolved/snoozed. `is_private`, `snoozed_until`
- `Message` — mensagem. `is_private: true` para notas internas
- `Property` — imóvel. `after_create_commit` dispara `PropertyMatchJob`
- `Inbox` — canal WhatsApp (Baileys)
- `Appointment` — agendamento de visita
- `Condominium` — condomínio/empreendimento
- `Tag` — etiquetas para conversas
- `Notification` — notificações in-app
- `PushSubscription` — para notificações push VAPID

## Jobs
- `PropertyMatchJob` — usa OpenAI para cruzar detalhes do imóvel com campo `intention` dos contatos. Broadcast via ActionCable quando encontra matches.

## Controllers Importantes
- `Admin::BaseController` — base para `/admin/*`, exige `role == admin`
- `Users::SessionsController` — login JWT, retorna user data no JSON
- `ConversationsController` — inclui lógica de transferência com nota privada (`transfer_note` param)
- `PropertiesController` — ação `trigger_match` para disparo manual de matching
- `BillingController` — integração Asaas

## Rotas Relevantes
```
POST /properties/:id/trigger_match   → disparo manual de matching
PUT  /conversations/:id              → aceita transfer_note param
namespace :admin → dashboard, accounts, support_tickets, settings
namespace :webhooks → baileys, stripe, canal_pro, zap, viva_real
```

## Autenticação
- Devise-JWT com JTI matcher
- `active_for_authentication?` verifica `status == 'active'`
- Super admin: `User` com `role: :admin` e `account` vinculado

## Deploy
1. Alterações em `crm_backend_check/`
2. `git add` + `git commit` + `git push`
3. Portainer: atualizar serviço backend
4. Rodar `bundle exec rails db:migrate` no container após deploy

## Comandos Úteis (via Portainer Exec no container backend)
```bash
bundle exec rails console          # console interativo
bundle exec rails db:migrate       # rodar migrations pendentes
bundle exec rails db:seed          # recriar dados iniciais (CUIDADO em prod)
```

## Repositório
GitHub: `https://github.com/balbiss/crm_inoovaweb_oficial`
Branch principal: `main`
