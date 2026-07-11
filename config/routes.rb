Rails.application.routes.draw do
  namespace :reports do
    get :overview
    get :by_agent
    get :by_tag
    get :export
    get :performance
  end
  resources :properties do
    member do
      post :trigger_match
    end
  end
  resources :condominiums
  resources :appointments do
    collection do
      get :report
      get :export
    end
  end
  resources :agents do
    member do
      patch :block
      patch :unblock
      patch :toggle_roundrobin
    end
    collection do
      get :queue
    end
  end
  resources :round_robin_groups, only: %i[index create update destroy]
  resources :contacts do
    member do
      post :merge
      post :add_note
      patch :block
      patch :unblock
    end
  end
  resources :tags
  get 'dashboard', to: 'dashboard#index'
  
  resources :conversations, only: [:index, :show, :update] do
    resources :messages, only: [:index, :create]
    resources :scheduled_messages, only: [:index, :create, :destroy]
    resources :tags, only: [:index, :create, :destroy], controller: 'conversation_tags'
    member do
      post :generate_summary
      get :ai_status
      post :resume_ai
      get :transcript
    end
  end

  resources :support_tickets, only: [:index, :show, :create] do
    resources :support_ticket_messages, only: [:create]
  end

  resources :notifications, only: [:index] do
    collection do
      put :mark_all_read
    end
    member do
      put :mark_as_read
    end
  end

  resource :account, only: [:show, :update] do
    put :update_password
    get :test_asaas
  end

  resources :contacts, only: [] do
    resources :charges, only: [:create], shallow: true
  end

  resources :inboxes do
    resources :members, controller: 'inbox_members', only: [:index, :create, :destroy]
    member do
      get :qr_code
      get :status
      post :generate_prompt
    end
  end

  get 'instagram_oauth/authorize_url', to: 'instagram_oauth#authorize_url'
  get 'instagram_oauth/callback',      to: 'instagram_oauth#callback'

  namespace :webhooks do
    post 'baileys',              to: 'baileys#create'
    post 'stripe',               to: 'stripe#create'
    post 'canal_pro/:token',     to: 'canal_pro#create', defaults: { source_portal: 'canal_pro' }
    post 'zap/:token',           to: 'canal_pro#create', defaults: { source_portal: 'zap' }
    post 'viva_real/:token',     to: 'canal_pro#create', defaults: { source_portal: 'viva_real' }
    get  'instagram',            to: 'instagram#verify'
    post 'instagram',            to: 'instagram#create'
  end

  namespace :admin do
    get 'dashboard', to: 'dashboard#index'
    get 'settings', to: 'settings#index'
    post 'settings', to: 'settings#create'
    resources :accounts, only: [:index, :create, :update, :destroy] do
      member do
        put :block
      end
    end
    
    resources :support_tickets, only: [:index, :show] do
      member do
        post :reply
        put :close
      end
    end
  end

  post 'register', to: 'registrations#create'

  get  'push_subscriptions/vapid_public_key', to: 'push_subscriptions#vapid_public_key'
  post 'push_subscriptions',                  to: 'push_subscriptions#create'
  delete 'push_subscriptions/unsubscribe',    to: 'push_subscriptions#unsubscribe'

  post 'billing/checkout', to: 'billing#checkout'
  post 'billing/portal', to: 'billing#portal'

  devise_for :users, controllers: {
    registrations: 'users/registrations',
    sessions: 'users/sessions',
    passwords: 'users/passwords'
  }

  get "up" => "rails/health#show", as: :rails_health_check

  mount ActionCable.server => '/cable'
end
