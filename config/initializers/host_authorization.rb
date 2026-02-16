# frozen_string_literal: true

# Disable host authorization in test environment
# Rails 8 blocks requests from unrecognized hosts by default
# In test environment, we need to allow requests from www.example.com used by RSpec
if Rails.env.test?
  Rails.application.config.hosts.clear
end
