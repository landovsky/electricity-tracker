# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
# Force RAILS_ENV to 'test' (don't use ||= as system env might have it set to development)
ENV['RAILS_ENV'] = 'test'
# Unset DATABASE_URL to use database.yml config for SQLite
ENV.delete('DATABASE_URL')
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
# Uncomment the line below in case you have `--require rails_helper` in the `.rspec` file
# that will avoid rails generators crashing because migrations haven't been run yet
# return unless Rails.env.test?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!
require 'capybara/rspec'
require 'database_cleaner/active_record'

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts "Loading schema from db/schema.rb"
  load Rails.root.join("db", "schema.rb")
end
RSpec.configure do |config|
  # Force English locale for tests
  config.before(:each) do
    I18n.locale = :en
  end

  # We're using FactoryBot, not fixtures
  config.use_transactional_fixtures = false

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails uses metadata to mix in different behaviours to your tests,
  # for example enabling you to call `get` and `post` in request specs. e.g.:
  #
  #     RSpec.describe UsersController, type: :request do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/7-1/rspec-rails
  #
  # You can also this infer these behaviours automatically by location, e.g.
  # /spec/models would pull in the same behaviour as `type: :model` but this
  # behaviour is considered legacy and will be removed in a future version.
  #
  # To enable this behaviour uncomment the line below.
  # config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  # Infer spec types from file location
  config.infer_spec_type_from_file_location!

  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # Database Cleaner configuration
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end

  config.before(:each, type: :system, js: true) do
    DatabaseCleaner.strategy = :deletion
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

  # Audited gem compatibility with Rails 8
  config.before(:suite) do
    # Suppress Audited deprecation warnings in test environment
    Audited.store[:audited_user] = nil if defined?(Audited)
  end

  # System test configuration
  # Use fast rack_test by default; use `js: true` tag for tests needing JavaScript
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  end

  # Include SystemHelpers for system tests
  config.include SystemHelpers, type: :system
end

# Configure Capybara for system tests
Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')  # Use new headless mode
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--disable-software-rasterizer')
  options.add_argument('--window-size=1400,1400')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.configure do |config|
  config.default_max_wait_time = 5
  config.server = :puma, { Silent: true }
  config.app_host = 'http://localhost'
  config.server_host = 'localhost'
  config.server_port = 3001 + ENV['TEST_ENV_NUMBER'].to_i
end
