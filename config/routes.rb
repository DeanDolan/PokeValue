# References:
# - Rails routing guide (resourceful routes, named routes, root):
#   https://guides.rubyonrails.org/routing.html
# - Rails REST conventions for controllers and actions:
#   https://guides.rubyonrails.org/action_controller_overview.html

Rails.application.routes.draw do
  # Portfolio as the homepage
  root "portfolios#index"
  get "/portfolio", to: "portfolios#index", as: :portfolio

  # Sets and products (nested via slug and product type)
  get "/sets",             to: "pages#sets",    as: :sets
  get "/sets/:slug",       to: "pages#set",     as: :set
  get "/sets/:slug/:type", to: "pages#product", as: :product

  # Static-style pages for marketplace / auction / raffle / showcase
  get "/marketplace", to: "pages#marketplace", as: :marketplace
  get "/auction",     to: "pages#auction",     as: :auction
  get "/raffle",      to: "pages#raffle",      as: :raffle
  get "/showcase",    to: "pages#showcase",    as: :showcase

  # Account page for logged-in user
  get "/account", to: "accounts#show", as: :account

  # Session-based auth (login / logout)
  get    "/login",  to: "sessions#new",     as: :login
  post   "/login",  to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  # Registration (sign up)
  get  "/register", to: "registrations#new",    as: :register
  post "/register", to: "registrations#create"

  # Global search JSON endpoint used by the navbar search bar
  get "/search_index",
      to: "pages#search_index",
      as: :search_index,
      defaults: { format: :json }

  # Holdings CRUD for portfolio table actions (create/edit/update/delete)
  resources :holdings, only: [ :create, :edit, :update, :destroy ]
end
