Rails.application.routes.draw do
  # Main navbar and search routes
  root "portfolios#index"
  get "/search_index", to: "pages#search_index", as: :search_index, defaults: { format: :json }

  # Sets, set, product and forecast routes
  get "/sets", to: "sets#index", as: :sets
  get "/sets/:slug", to: "sets#show", as: :set
  get "/sets/:slug/:type", to: "product#show", as: :set_product
  get "/forecast", to: "forecasts#show", defaults: { format: :json }

  # Portfolio routes
  get "/portfolio", to: "portfolios#index", as: :portfolio
  get "/portfolio/login_required", to: "portfolios#login_required", as: :portfolio_login_required
  get "/portfolio/metrics", to: "portfolios#metrics", as: :portfolio_metrics, defaults: { format: :json }

  # Summary routes
  resources :summary_entries, only: [ :destroy ]
  delete "/summary_entries/sold/:id", to: "summary_entries#destroy_sold", as: :sold_summary_entry

  # Admin routes
  namespace :admin do
    resources :product_values, param: :sku, only: [ :update ]

    get "/products", to: "products#index", as: :products
    patch "/products/update_product_values", to: "products#update_product_values", as: :update_product_values

    get "/sets", to: "sets#index", as: :sets
    patch "/sets/update_set_values", to: "sets#update_set_values", as: :update_set_values

    resources :raffles, only: [ :index, :destroy ]
  end

  # User and account routes
  get "/account", to: "accounts#show", as: :account
  get "/users/:id", to: redirect("/"), as: :user
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout
  post "/register", to: "registrations#create", as: :register
  get "/mfa", to: "mfa#new", as: :mfa
  post "/mfa", to: "mfa#create"
  get "/mfa/setup", to: "mfa#setup", as: :mfa_setup
  patch "/mfa/enable", to: "mfa#enable", as: :mfa_enable
  post "/watchlist/:sku", to: "watchlists#create", as: :watchlist
  delete "/watchlist/:sku", to: "watchlists#destroy", as: :remove_watchlist
  resources :saved_addresses, only: [ :create, :destroy ]

  resources :holdings, only: [ :create, :edit, :update, :destroy ] do
    member do
      get :sold
      post :mark_sold
    end
  end

  # Marketplace routes
  get "/marketplace", to: "marketplace_listings#index", as: :marketplace

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

  # Auction routes
  get "/auction", to: "pages#auction", as: :auction
  get "/auction/new", to: "auctions#new", as: :new_auction
  post "/auction", to: "auctions#create", as: :auctions
  get "/auction/:id", to: "auctions#show", as: :auction_listing
  get "/auction/:id/bid", to: "auctions#bid", as: :bid_auction
  post "/auction/:id/bid", to: "auctions#create_bid", as: :place_auction_bid
  post "/auction/:id/end", to: "auctions#end_auction", as: :end_auction
  delete "/auction/:id", to: "auctions#destroy", as: :delete_auction
  post "/auction/:id/confirm_payment", to: "auctions#confirm_payment", as: :confirm_auction_payment
  post "/auction/:id/verify_payment", to: "auctions#verify_payment", as: :verify_auction_payment

  # Raffle routes
  resources :raffles, only: [ :index, :new, :create, :show, :destroy ] do
    member do
      post :purchase_tickets
      post :return_tickets
      post :toggle_paid
      post :verify_payment
      post :run_raffle
    end
  end

  # Community routes
  get "/community", to: "pages#community", as: :community

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
end
