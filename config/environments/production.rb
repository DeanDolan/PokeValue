require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Keeps production code fixed between requests for speed and stability.
  config.enable_reloading = false

  # Loads the full application on boot for better production performance.
  config.eager_load = true

  # Hides full error reports from users in production.
  config.consider_all_requests_local = false

  # Enables fragment caching in production views.
  config.action_controller.perform_caching = true

  # Caches digest-stamped assets for a long time.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Stores uploaded files on the local file system in production.
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Sends logs to STDOUT and tags each request with its request id.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Sets the production log level from an environment variable, defaulting to info.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Keeps health check requests from filling the production logs.
  config.silence_healthcheck_path = "/up"

  # Disables deprecation reporting in production.
  config.active_support.report_deprecations = false

  # Uses Solid Cache instead of the default in-memory cache.
  config.cache_store = :solid_cache_store

  # Uses Solid Queue as the production background job backend.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Sets the host used for links generated inside mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Allows missing translations to fall back to the default locale.
  config.i18n.fallbacks = true

  # Stops Rails from dumping the schema after production migrations.
  config.active_record.dump_schema_after_migration = false

  # Limits model inspection output in production logs.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
