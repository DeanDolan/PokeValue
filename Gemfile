source "https://rubygems.org"

# Main Rails framework version used by the application.
gem "rails", "~> 8.1.1"

# Modern Rails asset pipeline.
gem "propshaft"

# SQLite database adapter.
gem "sqlite3", ">= 2.1"

# Web server used to run the Rails app.
gem "puma", ">= 5.0"

# JavaScript import map support.
gem "importmap-rails"

# Turbo support for faster page navigation.
gem "turbo-rails"

# Stimulus JavaScript framework support.
gem "stimulus-rails"

# Adds secure password hashing with has_secure_password.
gem "bcrypt", "~> 3.1"

# Time zone support for Windows.
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Database-backed Rails cache.
gem "solid_cache"

# Database-backed background jobs.
gem "solid_queue"

# Database-backed Action Cable.
gem "solid_cable"

# Speeds up Rails boot time.
gem "bootsnap", require: false

# Deployment tool.
gem "kamal", require: false

# HTTP caching/compression support.
gem "thruster", require: false

# Image processing support for Active Storage.
gem "image_processing", "~> 1.2"

group :development, :test do
  # Debugging support during development and testing.
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Checks gems for known security issues.
  gem "bundler-audit", require: false

  # Security scanner for Rails code.
  gem "brakeman", require: false

  # Rails style checker.
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Shows console on Rails error pages in development.
  gem "web-console"
end

group :test do
  # Rails 8.1 works correctly with Minitest 5 for Rails test runner compatibility.
  gem "minitest", "~> 5.25"

  # Browser/system testing support.
  gem "capybara"

  # Browser driver for system tests.
  gem "selenium-webdriver"
end

# Login throttling and basic rate limiting.
gem "rack-attack"
