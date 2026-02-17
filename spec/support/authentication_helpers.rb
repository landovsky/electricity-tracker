# frozen_string_literal: true

# Authentication helpers for request and system specs.
#
# For request specs: automatically stubs authentication so existing tests
# continue to work without modification. Use sign_in_as to change the user.
#
# For system specs: provides sign_in_via_magic_link for E2E auth flow.
module AuthenticationHelpers
  # Sign in via the full magic link flow (useful for system specs)
  def sign_in_via_magic_link(user)
    visit login_path
    fill_in "email", with: user.email
    click_button "Send login link"

    mail = ActionMailer::Base.deliveries.last
    body = mail.body.to_s
    token_match = body.match(%r{/auth/([^"'\s]+)})
    visit auth_verify_path(token: token_match[1])
  end
end

# Stub-based auth for request specs — fast and non-invasive
module RequestAuthenticationHelpers
  def sign_in_as(user)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:logged_in?).and_return(true)
  end
end

RSpec.configure do |config|
  config.include RequestAuthenticationHelpers, type: :request
  config.include AuthenticationHelpers, type: :system

  # Auto-sign in for all request specs with a default user.
  # Individual specs can override with sign_in_as(other_user).
  # SessionsController specs override with and_call_original.
  config.before(:each, type: :request) do
    default_user = User.kept.first || FactoryBot.create(:user)
    sign_in_as(default_user)
    ActionMailer::Base.deliveries.clear
  end

  config.before(:each, type: :system) do
    ActionMailer::Base.deliveries.clear
    # Auto-authenticate system specs by disabling auth.
    # Individual specs can test the auth flow by re-enabling it.
    ENV["DISABLE_AUTH"] = "true"
  end

  config.after(:each, type: :system) do
    ENV.delete("DISABLE_AUTH")
  end
end
