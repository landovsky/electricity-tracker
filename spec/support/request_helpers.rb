# frozen_string_literal: true

# Helper methods for request specs
# Provides CSRF token handling and authentication helpers
module RequestHelpers
  # Disable CSRF protection for request specs to avoid 403 Forbidden responses
  # In production, CSRF tokens will be properly handled by forms
  def bypass_csrf_protection
    ActionController::Base.allow_forgery_protection = false
  end

  # Re-enable CSRF protection (for cleanup)
  def restore_csrf_protection
    ActionController::Base.allow_forgery_protection = true
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request

  # Configure host authorization for request specs
  # Rails 8 blocks requests by default unless from allowed hosts
  config.before(:each, type: :request) do
    host! "www.example.com"
    bypass_csrf_protection
  end

  # Re-enable CSRF protection after each request spec
  config.after(:each, type: :request) do
    restore_csrf_protection
  end
end
