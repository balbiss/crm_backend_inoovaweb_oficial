Rails.application.routes.draw do
  resources :properties
  resources :condominiums
  resources :appointments
  resources :contacts do
    member do
      post :merge
      post :add_note
    end
  end
  get 'dashboard', to: 'dashboard#index'
  
  resources :conversations, only: [:index, :show, :update] do
    resources :messages, only: [:index, :create]
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
  end

  resources :inboxes do
    member do
      get :qr_code
      get :status
    end
  end
  
  namespace :webhooks do
    post 'baileys', to: 'baileys#create'
    post 'stripe', to: 'stripe#create'
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
