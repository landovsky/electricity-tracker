source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Business logic service objects
gem "active_interaction", "~> 5.3"

# Soft deletes
gem "discard", "~> 1.3"

# Audit trail
gem "audited", "~> 5.7"

# Normalize empty strings to nil
gem "nilify_blanks", "~> 1.4"

# View components
gem "view_component", "~> 4.5"

# Google reCAPTCHA verification
gem "recaptcha", "~> 5.17"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# S3-compatible storage (DigitalOcean Spaces)
gem "aws-sdk-s3"

# LLM integration (Gemini for meter photo classification)
gem "ruby_llm", "~> 1.0"

# Google Cloud auth (service account credentials for Vision API)
gem "googleauth", "~> 1.11"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Testing framework
  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "ffaker", "~> 2.23"
  gem "shoulda-matchers", "~> 6.4"
  gem "capybara", "~> 3.40"
  gem "selenium-webdriver", "~> 4.28"
  gem "database_cleaner-active_record", "~> 2.2"
end

# XLS file reading for data migration
gem "roo", "~> 2.10"
gem "roo-xls", "~> 2.0"

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Better console debugging
  gem "pry-rails", "~> 0.3"

  # Magic link email preview
  gem "letter_opener", "~> 1.10"
  gem "letter_opener_web", "~> 3.0"

  # Live reload on file changes (CSS, ERB, etc.)
  gem "hotwire-livereload"
end
