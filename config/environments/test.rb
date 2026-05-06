Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Disables reloading while tests are running.
  config.enable_reloading = false

  # Eager loads the app in CI so loading problems are caught before deployment.
  config.eager_load = ENV["CI"].present?

  # Serves public files with short caching during tests.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Shows full error reports during tests and disables caching.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Renders exception templates for rescuable exceptions and raises other errors.
  config.action_dispatch.show_exceptions = :rescuable

  # Disables CSRF protection in tests so test requests are simpler.
  config.action_controller.allow_forgery_protection = false

  # Stores uploaded files in the temporary test storage service.
  config.active_storage.service = :test

  # Stores test emails in ActionMailer::Base.deliveries instead of sending them.
  config.action_mailer.delivery_method = :test

  # Sets the host used for links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Prints deprecation notices to stderr during tests.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raises an error when before_action only/except options point to missing controller actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
