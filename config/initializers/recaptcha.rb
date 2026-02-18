# frozen_string_literal: true

Recaptcha.configure do |config|
  config.site_key = ENV["RECAPTCHA_SITE_KEY"]
  config.secret_key = ENV["RECAPTCHA_SECRET_KEY"]
  config.skip_verify_env << "test"

  if Rails.env.development? && (config.site_key.blank? || config.secret_key.blank?)
    config.skip_verify_env << "development"
  end
end
