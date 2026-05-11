Rails.application.routes.draw do
  # This is the first page the user sees when they open the app.
  # It sends the user straight to the portfolio dashboard.
  root "portfolios#index"

  # This gives the portfolio page a clean URL: /portfolio.
  # The "as: :portfolio" part creates the helper portfolio_path.
  get "/portfolio", to: "portfolios#index", as: :portfolio

  # This route returns portfolio metric data as JSON.
  # It is used when the portfolio page needs chart/metrics data such as total cost,
  # total value, unrealised profit/loss, ROI and realised profit/loss.
  get "/portfolio/metrics", to: "portfolios#metrics", as: :portfolio_metrics, defaults: { format: :json }

  # This route shows the main Sets page.
  # Users can see all Pokémon sets and use the search/filter on that page.
  get "/sets", to: "pages#sets", as: :sets

  # This route shows one specific set page.
  # The :slug is the set identifier in the URL.
  # Example: /sets/surging-sparks
  get "/sets/:slug", to: "pages#set", as: :set

  # This route shows a product page inside a specific set.
  # :slug identifies the set and :type identifies the product type/product route.
  # Example: /sets/surging-sparks/booster_box
  get "/sets/:slug/:type", to: "pages#product", as: :set_product

  # This is the main marketplace page.
  # It shows current listings and sold listings.
  get "/marketplace", to: "marketplace_listings#index", as: :marketplace

  # This route shows the Create Auction form.
  # The user fills this in when they want to host a new auction.
  get "/auction/new", to: "auctions#new", as: :new_auction

  # This route shows the main auction page.
  # It displays current auctions, ended auctions and sold auctions.
  get "/auction", to: "pages#auction", as: :auction

  # This route creates a new auction after the auction form is submitted.
  post "/auction", to: "auctions#create", as: :auctions

  # This route shows one auction in detail.
  # The :id is the auction record ID from the database.
  get "/auction/:id", to: "auctions#show", as: :auction_listing

  # This route shows the bid page for a specific auction.
  # It allows a user to enter a bid on an auction that is not their own.
  get "/auction/:id/bid", to: "auctions#bid", as: :bid_auction

  # This route submits a bid for a specific auction.
  # It updates the auction's highest bid if the bid is valid.
  post "/auction/:id/bid", to: "auctions#create_bid", as: :place_auction_bid

  # This route ends an auction.
  # It is used when an auction needs to be closed and the winning bidder is determined.
  post "/auction/:id/end", to: "auctions#end_auction", as: :end_auction

  # This route deletes an auction.
  # This is mainly used by admins or where the controller allows the correct user to remove it.
  delete "/auction/:id", to: "auctions#destroy", as: :delete_auction

  # This route is used when the winning bidder confirms that they have paid.
  post "/auction/:id/confirm_payment", to: "auctions#confirm_payment", as: :confirm_auction_payment

  # This route is used when the auction host/admin verifies that payment was received.
  post "/auction/:id/verify_payment", to: "auctions#verify_payment", as: :verify_auction_payment

  # These are the main raffle routes.
  # Rails creates standard routes for:
  # index   -> show all raffles
  # new     -> show the new raffle form
  # create  -> create a raffle
  # show    -> show one raffle
  # destroy -> delete/end a raffle
  resources :raffles, only: [ :index, :new, :create, :show, :destroy ] do
    member do
      # Buys tickets for one specific raffle.
      post :purchase_tickets

      # Returns tickets for one specific raffle if the controller allows it.
      post :return_tickets

      # Toggles whether a raffle-related payment has been marked as paid.
      post :toggle_paid

      # Verifies payment for a raffle.
      post :verify_payment

      # Runs the raffle winner selection.
      # This is used when all tickets are sold and the host starts the raffle/spin wheel.
      post :run_raffle
    end
  end

  # If someone types /raffle instead of /raffles, send them to the correct raffle page.
  get "/raffle", to: redirect("/raffles")

  # This route shows the community page.
  # Users can create posts, comment and react with emojis.
  get "/community", to: "pages#community", as: :community

  # Showcase was redirected to the community page.
  # This keeps the old /showcase URL working without needing a separate page.
  get "/showcase", to: redirect("/community")

  # This route shows the logged-in user's own account page.
  # It includes account details, funds, reviews, listings, auctions, watchlist and addresses.
  get "/account", to: "accounts#show", as: :account

  # This route shows a public user profile page.
  # It is used when clicking another user's username from marketplace, auction or raffle areas.
  get "/users/:id", to: "users#show", as: :user

  # This route shows the login form.
  get "/login", to: "sessions#new", as: :login

  # This route submits the login form.
  # It checks the username/password and creates the user session if valid.
  post "/login", to: "sessions#create"

  # This route logs the user out by destroying the current session.
  delete "/logout", to: "sessions#destroy", as: :logout

  # This route shows the registration form.
  get "/register", to: "registrations#new", as: :register

  # This route submits the registration form and creates a new user account.
  post "/register", to: "registrations#create"

  # This route returns the global search data as JSON.
  # The navbar search uses this to find sets and products.
  get "/search_index", to: "pages#search_index", as: :search_index, defaults: { format: :json }

  # This route calls the Rails forecast controller.
  # The Rails controller then talks to the separate Python forecasting service.
  get "/forecast", to: "forecasts#show", defaults: { format: :json }

  # This route shows the MFA code page.
  # It is used mainly for admin login verification.
  get "/mfa", to: "mfa#new", as: :mfa

  # This route submits the MFA code.
  post "/mfa", to: "mfa#create"

  # This route shows the MFA setup page.
  # It is used when setting up an authenticator app.
  get "/mfa/setup", to: "mfa#setup", as: :mfa_setup

  # This route enables MFA after setup is complete.
  patch "/mfa/enable", to: "mfa#enable", as: :mfa_enable

  # This route adds a product to the user's watchlist.
  # The :sku identifies the product being saved.
  post "/watchlist/:sku", to: "watchlists#create", as: :watchlist

  # This route removes a product from the user's watchlist.
  # The :sku identifies the product being removed.
  delete "/watchlist/:sku", to: "watchlists#destroy", as: :remove_watchlist

  # These routes allow users to create and delete saved addresses.
  # Saved addresses can be used for marketplace, auction or raffle delivery details.
  resources :saved_addresses, only: [ :create, :destroy ]

  # Admin routes are grouped inside /admin.
  # This keeps admin-only features separate from normal user features.
  namespace :admin do
    # Allows admins to update product values using the product SKU instead of the normal database ID.
    resources :product_values, param: :sku, only: [ :update ]

    # Admin products page.
    # The index route shows products and the collection route lets the admin update multiple values.
    resources :products, only: [ :index ] do
      collection do
        # Updates multiple product values from the admin products page.
        patch :update_values
      end
    end

    # Admin sets page.
    # Uses the set slug instead of the normal database ID.
    resources :sets, param: :slug, only: [ :index ] do
      collection do
        # Updates set values/details in bulk from the admin sets page.
        patch :update_values
      end

      member do
        # Updates one specific set.
        patch :update
      end
    end

    # Admin raffle routes.
    # Admin can view raffles and destroy/delete raffles if needed.
    resources :raffles, only: [ :index, :destroy ]
  end

  # These routes handle community posts.
  # Users can create posts, update their own posts and delete their own posts.
  resources :community_posts, only: [ :create, :update, :destroy ] do
    member do
      # Adds or changes an emoji reaction on a specific community post.
      post :react, to: "community_reactions#create"
    end

    # These routes handle comments that belong to a specific community post.
    resources :community_comments, only: [ :create ] do
      member do
        # Adds or changes an emoji reaction on a specific comment.
        post :react, to: "community_comment_reactions#create"
      end
    end
  end

  # This deletes normal portfolio summary history entries.
  # These entries appear when users view portfolio summary/history activity.
  resources :summary_entries, only: [ :destroy ]

  # This deletes a sold summary entry.
  # It is separate because sold entries may be handled differently from normal summary entries.
  delete "/summary_entries/sold/:id", to: "summary_entries#destroy_sold", as: :sold_summary_entry

  # Holding routes are used for portfolio products.
  # create  -> add product to portfolio
  # edit    -> show edit holding form
  # update  -> save edited holding
  # destroy -> remove holding from portfolio
  resources :holdings, only: [ :create, :edit, :update, :destroy ]

  # Reviews are created after marketplace, auction or raffle interactions.
  resources :reviews, only: [ :create ]

  # Funds routes are used when a user adds funds to their account balance.
  resources :funds, only: [ :new, :create ]

  # These are the main marketplace listing routes.
  # index   -> show all marketplace listings
  # new     -> show create listing form
  # create  -> create a listing
  # show    -> view one listing
  # edit    -> edit a listing
  # update  -> save listing changes
  # destroy -> delete a listing
  resources :marketplace_listings, only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
    member do
      # Cancels a listing.
      post :cancel

      # Creates an offer on a specific marketplace listing.
      post :create_offer

      # Accepts an offer on a specific marketplace listing.
      post :accept_offer

      # Shows the payment page for a marketplace listing.
      get :pay

      # Buyer confirms that payment has been made.
      post :confirm_payment

      # Seller/admin confirms that payment has been received.
      post :confirm_paid
    end
  end
end
