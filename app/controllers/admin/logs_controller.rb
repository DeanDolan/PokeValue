module Admin
  class LogsController < ApplicationController
    def index
      return redirect_to(root_path, alert: "Forbidden.") unless admin_ok?

      @mode = params[:mode].to_s.strip
      @mode = "marketplace" unless %w[marketplace auction raffle].include?(@mode)

      @tab = params[:tab].to_s.strip

      if @mode == "auction"
        @tab = "auctions" unless %w[auctions ended sold deleted].include?(@tab)
        load_auction_logs
      elsif @mode == "raffle"
        @tab = "current_raffles" unless %w[current_raffles mini_raffles incompleted completed deleted].include?(@tab)
        load_raffle_logs
      else
        @tab = "listings" unless %w[listings sales refunds deleted].include?(@tab)
        load_marketplace_logs
      end
    end

    private

    def admin_ok?
      ok = false
      begin
        ok = true if respond_to?(:admin_signed_in?) && admin_signed_in?
      rescue
      end
      return true if ok

      u = User.find_by(id: session[:user_id]) rescue nil
      return false unless u

      if u.respond_to?(:admin?)
        return true if u.admin?
      end
      if u.respond_to?(:admin)
        return true if !!u.admin
      end
      false
    rescue
      false
    end

    def table_exists?(model)
      return false unless model
      return false unless model.respond_to?(:table_name)
      ActiveRecord::Base.connection.data_source_exists?(model.table_name)
    rescue
      false
    end

    def col_exists?(model, col)
      return false unless model && col.present?
      return false unless table_exists?(model)
      ActiveRecord::Base.connection.column_exists?(model.table_name, col.to_s)
    rescue
      false
    end

    def assoc_exists?(model, assoc)
      return false unless model
      model.reflect_on_association(assoc).present?
    rescue
      false
    end

    def load_marketplace_logs
      @listings = []
      @sales = []
      @refunds = []
      @deleted_listings = []

      case @tab
      when "sales"
        load_marketplace_sales
      when "refunds"
        load_marketplace_refunds
      when "deleted"
        load_marketplace_deleted
      else
        load_marketplace_current
      end
    end

    def load_marketplace_current
      @listings =
        if MarketplaceListing.respond_to?(:active)
          MarketplaceListing.active.includes(:seller).order(created_at: :desc).limit(500).to_a
        else
          MarketplaceListing.where(status: "active").includes(:seller).order(created_at: :desc).limit(500).to_a
        end
    rescue
      @listings = []
    end

    def load_marketplace_sales
      if defined?(MarketplacePurchase) && table_exists?(MarketplacePurchase)
        scope = MarketplacePurchase.all

        if col_exists?(MarketplacePurchase, "refunded")
          scope = scope.where(refunded: false)
        elsif col_exists?(MarketplacePurchase, "refunded_at")
          scope = scope.where(refunded_at: nil)
        elsif col_exists?(MarketplacePurchase, "status")
          scope = scope.where(status: "sold")
        end

        @sales = scope.order(created_at: :desc).limit(500).to_a
      else
        @sales =
          if MarketplaceListing.respond_to?(:where)
            MarketplaceListing.where(status: "sold").includes(:seller).order(updated_at: :desc).limit(500).to_a
          else
            []
          end
      end
    rescue
      @sales = []
    end

    def load_marketplace_refunds
      if defined?(MarketplacePurchase) && table_exists?(MarketplacePurchase)
        scope = MarketplacePurchase.all

        if col_exists?(MarketplacePurchase, "refunded")
          scope = scope.where(refunded: true)
        elsif col_exists?(MarketplacePurchase, "refunded_at")
          scope = scope.where.not(refunded_at: nil)
        elsif col_exists?(MarketplacePurchase, "status")
          scope = scope.where(status: "refunded")
        else
          scope = MarketplacePurchase.none
        end

        @refunds = scope.order(created_at: :desc).limit(500).to_a
      else
        @refunds = []
      end
    rescue
      @refunds = []
    end

    def load_marketplace_deleted
      @deleted_listings =
        if col_exists?(MarketplaceListing, "status")
          MarketplaceListing.where(status: "deleted").includes(:seller).order(updated_at: :desc).limit(500).to_a
        else
          []
        end
    rescue
      @deleted_listings = []
    end

    def load_auction_logs
      @auctions = []
      return unless defined?(Auction)
      return unless table_exists?(Auction)

      begin
        Auction.refresh_all_statuses! if Auction.respond_to?(:refresh_all_statuses!)
      rescue
      end

      scope = Auction.all
      scope = scope.includes(:seller) if assoc_exists?(Auction, :seller)
      scope = scope.includes(:winning_bidder) if assoc_exists?(Auction, :winning_bidder)

      if col_exists?(Auction, "status")
        scope =
          case @tab
          when "ended"
            scope.where(status: "ended")
          when "sold"
            scope.where(status: "sold")
          when "deleted"
            scope.where(status: "deleted")
          else
            scope.where.not(status: %w[ended sold deleted])
          end
      else
        if @tab == "ended" && col_exists?(Auction, "ends_at")
          scope = scope.where("ends_at <= ?", Time.current)
        elsif @tab == "auctions" && col_exists?(Auction, "ends_at")
          scope = scope.where("ends_at > ?", Time.current)
        end
      end

      @auctions = scope.order(created_at: :desc).limit(500).to_a
    rescue
      @auctions = []
    end

    def load_raffle_logs
      @raffles = []
      return unless defined?(Raffle)
      return unless table_exists?(Raffle)

      scope = Raffle.all
      scope = scope.includes(:seller) if assoc_exists?(Raffle, :seller)
      scope = scope.includes(:user) if assoc_exists?(Raffle, :user)
      scope = scope.includes(:creator) if assoc_exists?(Raffle, :creator)

      scope =
        case @tab
        when "mini_raffles"
          raffle_mini_scope(raffle_active_scope(scope), true)
        when "completed"
          raffle_completed_scope(scope)
        when "incompleted"
          raffle_incompleted_scope(scope)
        when "deleted"
          raffle_deleted_scope(scope)
        else
          raffle_mini_scope(raffle_active_scope(scope), false)
        end

      if col_exists?(Raffle, "updated_at")
        scope = scope.order(updated_at: :desc)
      elsif col_exists?(Raffle, "created_at")
        scope = scope.order(created_at: :desc)
      end

      @raffles = scope.limit(500).to_a
    rescue
      @raffles = []
    end

    def raffle_active_scope(scope)
      model = scope.klass

      if col_exists?(model, "status")
        scope.where(status: [ nil, "", "active", "open", "current", "running", "in_progress" ])
      elsif col_exists?(model, "completed")
        scope.where(completed: [ false, nil ])
      elsif col_exists?(model, "completed_at")
        scope.where(completed_at: nil)
      elsif col_exists?(model, "ends_at")
        scope.where("ends_at > ?", Time.current)
      else
        scope
      end
    rescue
      scope
    end

    def raffle_completed_scope(scope)
      model = scope.klass

      if col_exists?(model, "status")
        scope.where(status: %w[completed complete])
      elsif col_exists?(model, "completed")
        scope.where(completed: true)
      elsif col_exists?(model, "completed_at")
        scope.where.not(completed_at: nil)
      else
        scope.none
      end
    rescue
      scope.none
    end

    def raffle_incompleted_scope(scope)
      model = scope.klass

      if col_exists?(model, "status")
        scope.where(status: %w[incompleted incomplete ended closed expired cancelled canceled])
      elsif col_exists?(model, "completed") && col_exists?(model, "ends_at")
        scope.where(completed: [ false, nil ]).where("ends_at <= ?", Time.current)
      elsif col_exists?(model, "ends_at")
        scope.where("ends_at <= ?", Time.current)
      else
        scope.none
      end
    rescue
      scope.none
    end

    def raffle_deleted_scope(scope)
      model = scope.klass

      if col_exists?(model, "status")
        scope.where(status: "deleted")
      elsif col_exists?(model, "deleted_at")
        scope.where.not(deleted_at: nil)
      elsif col_exists?(model, "discarded_at")
        scope.where.not(discarded_at: nil)
      else
        scope.none
      end
    rescue
      scope.none
    end

    def raffle_mini_scope(scope, mini)
      model = scope.klass

      %w[mini is_mini mini_raffle is_mini_raffle].each do |col|
        if col_exists?(model, col)
          return scope.where(col => mini)
        end
      end

      %w[raffle_type raffle_kind kind category mode].each do |col|
        if col_exists?(model, col)
          quoted_col = ActiveRecord::Base.connection.quote_column_name(col)
          if mini
            return scope.where("LOWER(#{quoted_col}) LIKE ?", "%mini%")
          else
            return scope.where.not("LOWER(#{quoted_col}) LIKE ?", "%mini%")
          end
        end
      end

      scope
    rescue
      scope
    end
  end
end
