Rails.application.routes.draw do
  root "portfolios#index"
  get "/portfolio", to: "portfolios#index", as: :portfolio

  get "/sets",             to: "pages#sets",    as: :sets
  get "/sets/:slug",       to: "pages#set",     as: :set
  get "/sets/:slug/:type", to: "pages#product", as: :set_product

  get "/marketplace", to: "pages#marketplace", as: :marketplace
  get "/auction",     to: "pages#auction",     as: :auction
  get "/raffle",      to: "pages#raffle",      as: :raffle
  get "/showcase",    to: "pages#showcase",    as: :showcase

  get "/account", to: "accounts#show", as: :account

  get    "/login",  to: "sessions#new",     as: :login
  post   "/login",  to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  get  "/register", to: "registrations#new", as: :register
  post "/register", to: "registrations#create"

  get "/search_index", to: "pages#search_index", as: :search_index, defaults: { format: :json }
  get "/forecast", to: "forecasts#show", defaults: { format: :json }

  get  "/mfa",         to: "mfa#new",   as: :mfa
  post "/mfa",         to: "mfa#create"
  get  "/mfa/setup",   to: "mfa#setup", as: :mfa_setup
  patch "/mfa/enable", to: "mfa#enable", as: :mfa_enable

  post   "/watchlist/:sku", to: "watchlists#create",  as: :watchlist
  delete "/watchlist/:sku", to: "watchlists#destroy", as: :remove_watchlist

  namespace :admin do
    resources :product_values, param: :sku, only: [ :update ]
  end

  resources :holdings, only: [ :create, :edit, :update, :destroy ]
end
