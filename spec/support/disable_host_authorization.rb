# frozen_string_literal: true

# Disable ActionDispatch::HostAuthorization in test environment
# This middleware blocks requests unless the host is explicitly allowed
# In test environment, we want to allow all requests to pass through

RSpec.configure do |config|
  config.before(:suite) do
    Rails.application.config.hosts.clear
    # Explicitly allow all hosts by setting to empty array
    Rails.application.config.host_authorization = {  exclude: ->(request) { Rails.env.test? } }
  end
end
