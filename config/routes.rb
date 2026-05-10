Rails.application.routes.draw do
  # Main dashboard route
  root "portfolios#index"
  get "/portfolio", to: "portfolios#index", as: :portfolio
  get "/portfolio/metrics", to: "portfolios#metrics", as: :portfolio_metrics, defaults: { format: :json }

  # Set and product browsing routes
  get "/sets", to: "pages#sets", as: :sets
  get "/sets/:slug", to: "pages#set", as: :set
  get "/sets/:slug/:type", to: "pages#product", as: :set_product

  # Marketplace and auction routes
  get "/marketplace", to: "marketplace_listings#index", as: :marketplace
  get "/auction/new", to: "auctions#new", as: :new_auction
  get "/auction", to: "pages#auction", as: :auction
  post "/auction", to: "auctions#create", as: :auctions
  get "/auction/:id", to: "auctions#show", as: :auction_listing
  get "/auction/:id/bid", to: "auctions#bid", as: :bid_auction
  post "/auction/:id/bid", to: "auctions#create_bid", as: :place_auction_bid
  post "/auction/:id/end", to: "auctions#end_auction", as: :end_auction
  delete "/auction/:id", to: "auctions#destroy", as: :delete_auction
  post "/auction/:id/confirm_payment", to: "auctions#confirm_payment", as: :confirm_auction_payment
  post "/auction/:id/verify_payment", to: "auctions#verify_payment", as: :verify_auction_payment

  # Raffle routes, including ticket and payment actions for a single raffle
  resources :raffles, only: [ :index, :new, :create, :show, :destroy ] do
    member do
      post :purchase_tickets
      post :return_tickets
      post :toggle_paid
      post :verify_payment
      post :run_raffle
    end
  end
  get "/raffle", to: redirect("/raffles")

  # Community and showcase routes
  get "/community", to: "pages#community", as: :community
  get "/showcase", to: redirect("/community")

  # Account and public profile routes
  get "/account", to: "accounts#show", as: :account
  get "/users/:id", to: "users#show", as: :user

  # Login, logout and registration routes
  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  get "/register", to: "registrations#new", as: :register
  post "/register", to: "registrations#create"

  # JSON routes used by search and forecasting features
  get "/search_index", to: "pages#search_index", as: :search_index, defaults: { format: :json }
  get "/forecast", to: "forecasts#show", defaults: { format: :json }

  # Multi-factor authentication routes
  get "/mfa", to: "mfa#new", as: :mfa
  post "/mfa", to: "mfa#create"
  get "/mfa/setup", to: "mfa#setup", as: :mfa_setup
  patch "/mfa/enable", to: "mfa#enable", as: :mfa_enable

  # Watchlist routes using the product SKU as the identifier
  post "/watchlist/:sku", to: "watchlists#create", as: :watchlist
  delete "/watchlist/:sku", to: "watchlists#destroy", as: :remove_watchlist

  # Saved delivery or marketplace address routes
  resources :saved_addresses, only: [ :create, :destroy ]

  # Admin-only routes for product values, sets and raffles
  namespace :admin do
    resources :product_values, param: :sku, only: [ :update ]

    resources :products, only: [ :index ] do
      collection do
        patch :update_values
      end
    end

    resources :sets, param: :slug, only: [ :index ] do
      collection do
        patch :update_values
      end

      member do
        patch :update
      end
    end

    resources :raffles, only: [ :index, :destroy ]
  end

  # Community post, comment and reaction routes
  resources :community_posts, only: [ :create, :update, :destroy ] do
    member do
      post :react, to: "community_reactions#create"
    end

    resources :community_comments, only: [ :create ] do
      member do
        post :react, to: "community_comment_reactions#create"
      end
    end
  end

  # Portfolio summary history routes
  resources :summary_entries, only: [ :destroy ]
  delete "/summary_entries/sold/:id", to: "summary_entries#destroy_sold", as: :sold_summary_entry

  # Main resource routes for holdings, reviews, funds and marketplace listings
  resources :holdings, only: [ :create, :edit, :update, :destroy ]
  resources :reviews, only: [ :create ]
  resources :funds, only: [ :new, :create ]

  resources :marketplace_listings, only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
    member do
      post :cancel
      post :create_offer
      post :accept_offer
      get :pay
      post :confirm_payment
      post :confirm_paid
    end
  end
end
