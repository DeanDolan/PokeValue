module AuctionsHelper
  AUCTION_CONDITIONS = [
    "Mint Condition",
    "Loosely Sealed",
    "Unsealed",
    "Big Tear",
    "Small Tear",
    "Big Imperfections",
    "Small Imperfections",
    "Pressure Marks",
    "Slightly Dented",
    "Heavy Dented",
    "Damaged",
    "Box Only",
    "Contents Only"
  ].freeze

  AUCTION_PAYMENT_WAITING_STATUSES = %w[
    payment_pending
    awaiting_payment
    awaiting_payment_verification
    payment_confirmed
    paid
    pending_payment
    pending_verification
  ].freeze

  # Conditions reused by auction create and filter forms.
  def auction_conditions
    AUCTION_CONDITIONS
  end

  # Auction duration options reused by the form and controller.
  def auction_duration_select_options
    Auction::DURATION_OPTIONS.map { |key, data| [ data[:label], key ] }
  end

  # EU country options for the auction location filter.
  def auction_country_options
    if defined?(CountriesHelper::COUNTRIES)
      CountriesHelper::COUNTRIES.map { |name, code| [ code, "#{auction_flag(code)} #{name}" ] }
    elsif respond_to?(:eu_countries)
      eu_countries.map { |country| [ country[:code], "#{country[:flag]} #{country[:name]}" ] }
    else
      []
    end
  end

  # Converts a country code into a flag emoji.
  def auction_flag(code)
    return flag_emoji(code) if respond_to?(:flag_emoji)

    code.to_s.upcase.chars.map { |char| (127397 + char.ord).chr(Encoding::UTF_8) }.join
  rescue
    "🌍"
  end

  # Returns a country name for hover text.
  def auction_country_name(code)
    return country_name(code) if respond_to?(:country_name)

    code.to_s.upcase
  rescue
    code.to_s
  end

  # Checks if a user has admin access.
  def auction_admin_user?(user)
    return false unless user
    return true if user.respond_to?(:admin?) && user.admin?
    return true if user.respond_to?(:admin) && !!user.admin

    false
  rescue
    false
  end

  # Returns badge images for a seller.
  def auction_badges_for(user)
    auction_admin_user?(user) ? [ "badges/adminbadge.png" ] : []
  end

  # Builds a simple star rating display.
  def auction_star_rating(avg, prefix: "pv-au")
    value = avg.to_f.clamp(0.0, 5.0)
    rounded = ((value * 2).round / 2.0)
    full = rounded.floor
    half = (rounded - full) >= 0.5

    parts = []
    full.times { parts << content_tag(:span, "★", class: "#{prefix}-star") }
    parts << content_tag(:span, "½", class: "#{prefix}-half") if half

    content_tag(:span, safe_join(parts), class: "#{prefix}-stars")
  end

  # Gets average review score and review count for visible sellers.
  def auction_review_stats_for_ids(seller_ids)
    ids = Array(seller_ids).compact.uniq
    return {} if ids.empty? || !defined?(Review)

    averages = Review.where(seller_id: ids).group(:seller_id).average(:rating)
    counts = Review.where(seller_id: ids).group(:seller_id).count

    ids.each_with_object({}) do |id, hash|
      hash[id] = {
        avg: averages[id].to_f,
        count: counts[id].to_i
      }
    end
  rescue
    {}
  end

  # Checks if an auction is in a payment state but still needs action.
  def auction_payment_waiting_status?(status)
    AUCTION_PAYMENT_WAITING_STATUSES.include?(status.to_s.downcase)
  end

  # Converts an auction record into the table tab status.
  def auction_status_key(auction)
    status = auction.status.to_s.downcase

    return "sold" if status == "sold"
    return "running" if auction_payment_waiting_status?(status)
    return "ended" if status == "ended"
    return "ended" if auction.ends_at.present? && auction.ends_at <= Time.current

    "running"
  end

  # Displays the stored auction length.
  def auction_length_label(auction)
    return auction.auction_length_label.to_s if auction.auction_length_label.present?

    Auction.label_for_seconds(auction.auction_length_seconds)
  end

  # Formats countdown text for tables and pages.
  def auction_time_left_text(auction)
    status_key = auction_status_key(auction)
    status = auction.status.to_s.downcase

    return auction_length_label(auction) if status_key != "running"
    return auction_length_label(auction) if auction_payment_waiting_status?(status)
    return "-" if auction.ends_at.blank?

    seconds = (auction.ends_at.to_f - Time.current.to_f).to_i
    return "Ended" if seconds <= 0

    days = seconds / 86_400
    hours = (seconds % 86_400) / 3_600
    minutes = (seconds % 3_600) / 60
    secs = seconds % 60

    return "#{days}d #{hours}h #{minutes}m" if days.positive?
    return "#{hours}h #{minutes}m #{secs}s" if hours.positive?

    "#{minutes}m #{secs}s"
  end

  # Converts the auction status into user-facing text.
  def auction_status_label(auction)
    case auction.status.to_s
    when "sold"
      "Sold"
    when "paid"
      "Payment Confirmed"
    when "payment_pending"
      "Awaiting Winner Payment"
    when "ended"
      "Ended"
    else
      auction.ends_at.present? && auction.ends_at <= Time.current ? "Ended" : "Running"
    end
  end

  # Bootstrap badge class for auction status.
  def auction_status_badge_class(auction)
    case auction.status.to_s
    when "sold"
      "bg-danger"
    when "paid"
      "bg-primary"
    when "payment_pending"
      "bg-warning text-dark"
    when "ended"
      "bg-secondary"
    else
      "bg-success"
    end
  end

  # Gets up to four uploaded auction images.
  def auction_images_for(auction)
    return [] unless auction.respond_to?(:photos) && auction.photos.attached?

    auction.photos.to_a.first(4)
  rescue
    []
  end
end
