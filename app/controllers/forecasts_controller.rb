class ForecastsController < ApplicationController
  require "net/http"
  require "uri"
  require "json"

  SERVICE_BASE = ENV.fetch("FORECAST_SERVICE_URL", "http://127.0.0.1:8000").to_s

  def show
    raw_set_name      = params[:set_name].to_s
    raw_product_name  = params[:product_name].to_s
    raw_category      = params[:product_category].to_s
    raw_variant       = params[:product_variant].to_s
    raw_origin        = params[:origin].to_s

    set_name = clean(raw_set_name)
    product_name = clean(raw_product_name)
    product_category = clean(raw_category)
    product_variant = clean(raw_variant)
    origin = clean(raw_origin)

    if set_name.blank?
      return render json: {
        ok: false,
        error: "bad_request",
        message: "set_name is required",
        params: safe_params(set_name, product_name, product_category, product_variant, origin)
      }, status: 400
    end

    if product_name.blank? && product_category.blank?
      return render json: {
        ok: false,
        error: "bad_request",
        message: "product_name or product_category is required",
        params: safe_params(set_name, product_name, product_category, product_variant, origin)
      }, status: 400
    end

    mapped_set = map_set_name(set_name)

    if product_variant.blank?
      v = infer_variant_from_product_name(product_name)
      product_variant = v if v.present?
    end

    if origin.blank?
      o = infer_origin_from_product_name(product_name)
      origin = o if o.present?
    end

    if product_category.blank?
      product_category = infer_category_from_product_name(product_name)
    end

    attempts = []
    attempt_logs = []
    last_response = nil

    build_attempt_queries(
      set_name: mapped_set,
      product_name: product_name,
      product_category: product_category,
      product_variant: product_variant,
      origin: origin
    ).each do |q|
      service_url = "#{SERVICE_BASE}/forecast?#{URI.encode_www_form(q)}"
      status, body, parsed = http_get(service_url)

      attempt_logs << {
        service_url: service_url,
        status: status,
        body_preview: preview(body)
      }

      last_response = parsed || (body.present? ? { raw: body } : nil)

      if status == 200 && parsed.is_a?(Hash)
        parsed["meta"] ||= {}
        parsed["meta"]["requested"] = {
          set_name: set_name,
          product_name: product_name,
          product_category: product_category,
          product_variant: product_variant,
          origin: origin
        }
        parsed["meta"]["used"] = {
          set_name: q["set_name"],
          product_name: q["product_name"],
          product_category: q["product_category"],
          product_variant: q["product_variant"],
          origin: q["origin"]
        }
        parsed["meta"]["service_url"] = service_url
        return render json: parsed
      end

      if status == 404 && parsed.is_a?(Hash)
        guesses = extract_guesses(parsed)
        if guesses.any?
          filtered = filter_guesses(
            guesses: guesses,
            requested_product_name: product_name,
            product_variant: product_variant,
            origin: origin
          )

          filtered.each do |g|
            q2 = q.merge("product_name" => g)
            service_url2 = "#{SERVICE_BASE}/forecast?#{URI.encode_www_form(q2)}"
            status2, body2, parsed2 = http_get(service_url2)

            attempt_logs << {
              service_url: service_url2,
              status: status2,
              body_preview: preview(body2)
            }

            last_response = parsed2 || (body2.present? ? { raw: body2 } : nil)

            if status2 == 200 && parsed2.is_a?(Hash)
              parsed2["meta"] ||= {}
              parsed2["meta"]["requested"] = {
                set_name: set_name,
                product_name: product_name,
                product_category: product_category,
                product_variant: product_variant,
                origin: origin
              }
              parsed2["meta"]["used"] = {
                set_name: q2["set_name"],
                product_name: q2["product_name"],
                product_category: q2["product_category"],
                product_variant: q2["product_variant"],
                origin: q2["origin"]
              }
              parsed2["meta"]["service_url"] = service_url2
              parsed2["meta"]["matched"] = true
              parsed2["meta"]["matched_product_name"] = g
              return render json: parsed2
            end
          end
        end
      end
    end

    status_code = 404
    if attempt_logs.any? { |a| a[:status].to_i >= 500 || a[:status].to_i == 0 }
      status_code = 502
    end

    render json: {
      ok: false,
      error: "forecast_service_error",
      message: "Forecast request failed",
      params: safe_params(set_name, product_name, product_category, product_variant, origin),
      attempts: attempt_logs,
      last_response: last_response
    }, status: status_code
  end

  private

  def clean(s)
    s.to_s.strip
  end

  def preview(body)
    b = body.to_s
    return "" if b.blank?
    b.length > 500 ? "#{b[0, 500]}..." : b
  end

  def safe_params(set_name, product_name, product_category, product_variant, origin)
    {
      set_name: set_name,
      product_name: product_name,
      product_category: product_category,
      product_variant: product_variant,
      origin: origin
    }
  end

  def map_set_name(set_name)
    ci = set_name.to_s.downcase.strip
    return "Celebrations" if ci.include?("celebrations") && ci.include?("classic collection")
    set_name
  end

  def infer_variant_from_product_name(product_name)
    m = product_name.to_s.match(/\(([^)]+)\)/)
    m ? m[1].to_s.strip : ""
  end

  def infer_origin_from_product_name(product_name)
    n = product_name.to_s.downcase
    return "Pokemon Center" if n.include?("pokemon center")
    ""
  end

  def infer_category_from_product_name(product_name)
    n = product_name.to_s.downcase
    return "PC ETB"   if n.include?("pokemon center") && n.include?("elite trainer box")
    return "ETB"      if n.include?("elite trainer box")
    return "BBox"     if n.include?("booster box")
    return "BBunDis"  if n.include?("booster bundle display")
    return "BBundle"  if n.include?("booster bundle")
    return "UPC/SPC"  if n.include?("ultra premium collection") || n.include?("super premium collection") || n.include?(" upc") || n.include?(" spc")
    ""
  end

  def build_attempt_queries(set_name:, product_name:, product_category:, product_variant:, origin:)
    queries = []

    base_name = product_name.to_s.strip
    base_name_no_set = base_name

    if base_name_no_set.downcase.start_with?(set_name.downcase + " ")
      base_name_no_set = base_name_no_set[(set_name.length + 1)..] || ""
    end

    base_no_paren = base_name_no_set.gsub(/\s*\([^)]+\)\s*/, " ").strip
    base_no_paren = base_no_paren.gsub(/\s+/, " ")

    base_for_origin = base_no_paren
    if origin.to_s.strip.casecmp("Pokemon Center") == 0
      if base_for_origin.downcase.include?("elite trainer box") && !base_for_origin.downcase.include?("pokemon center")
        base_for_origin = "Pokemon Center #{base_for_origin}".strip
      end
    end

    if base_name.present?
      queries << { "set_name" => set_name, "product_name" => base_name }
      queries << { "set_name" => set_name, "product_name" => base_name, "product_variant" => product_variant, "origin" => origin }.reject { |_, v| v.blank? }
    end

    if base_no_paren.present? && base_no_paren != base_name
      queries << { "set_name" => set_name, "product_name" => base_no_paren }
      queries << { "set_name" => set_name, "product_name" => base_for_origin }.reject { |_, v| v.blank? }
    end

    if base_no_paren.present?
      queries << { "set_name" => set_name, "product_name" => "#{set_name} #{base_no_paren}".strip }
      queries << { "set_name" => set_name, "product_name" => "#{set_name} #{base_for_origin}".strip }.reject { |_, v| v.blank? }
    end

    if product_variant.present? && base_no_paren.present?
      if base_for_origin.downcase.include?("elite trainer box") || base_for_origin.downcase.include?("booster box")
        queries << { "set_name" => set_name, "product_name" => "#{set_name} (#{product_variant}) #{base_for_origin}".strip }
      end
    end

    if product_variant.present? && base_name.present? && !base_name.include?("(")
      if base_for_origin.downcase.include?("elite trainer box") || base_for_origin.downcase.include?("booster box")
        queries << { "set_name" => set_name, "product_name" => "#{set_name} (#{product_variant}) #{base_for_origin}".strip }
      end
    end

    if product_variant.present? && base_name.present? && base_name.include?("(")
      queries << { "set_name" => set_name, "product_name" => "#{set_name} #{base_name_no_set}".strip }
    end

    if product_variant.blank? && origin.blank? && product_category.present?
      queries << { "set_name" => set_name, "product_category" => product_category }
    end

    dedup = {}
    out = []
    queries.each do |q|
      q = q.reject { |_, v| v.blank? }
      next if q.empty?
      key = q.to_a.sort.map { |k, v| "#{k}=#{v}" }.join("&")
      next if dedup[key]
      dedup[key] = true
      out << q
    end

    out
  end

  def extract_guesses(parsed)
    detail = parsed["detail"]
    return [] unless detail.is_a?(Hash)
    g = detail["guesses"]
    return [] unless g.is_a?(Array)
    g.map(&:to_s).reject(&:blank?)
  end

  def filter_guesses(guesses:, requested_product_name:, product_variant:, origin:)
    req = requested_product_name.to_s.downcase
    req_no_paren = req.gsub(/\s*\([^)]+\)\s*/, " ").strip

    filtered = guesses.dup

    if product_variant.present?
      v = product_variant.to_s.downcase
      filtered = filtered.select { |g| g.to_s.downcase.include?(v) }
    end

    if origin.present?
      o = origin.to_s.downcase
      filtered = filtered.select { |g| g.to_s.downcase.include?(o) }
    end

    if filtered.empty?
      filtered = guesses.select do |g|
        g2 = g.to_s.downcase
        sim = similarity(req_no_paren, g2.gsub(/\s*\([^)]+\)\s*/, " ").strip)
        sim >= 0.55
      end
    end

    filtered.first(5)
  end

  def similarity(a, b)
    a_tokens = a.to_s.downcase.split(/\s+/).reject(&:blank?)
    b_tokens = b.to_s.downcase.split(/\s+/).reject(&:blank?)
    return 0.0 if a_tokens.empty? || b_tokens.empty?
    inter = (a_tokens & b_tokens).length.to_f
    union = (a_tokens | b_tokens).length.to_f
    return 0.0 if union == 0.0
    inter / union
  end

  def http_get(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 3
    http.read_timeout = 20

    req = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(req)

    body = res.body.to_s
    parsed = begin
      JSON.parse(body)
    rescue StandardError
      nil
    end

    [ res.code.to_i, body, parsed ]
  rescue StandardError => e
    [ 0, "", { "error" => "http_error", "message" => "#{e.class}: #{e.message}" } ]
  end
end
