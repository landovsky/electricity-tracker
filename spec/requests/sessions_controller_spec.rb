# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionsController, type: :request do
  # SessionsController tests need real auth behavior, not stubs.
  # Override the RequestAuthenticationHelpers stub for these tests.
  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_call_original
    allow_any_instance_of(ApplicationController).to receive(:logged_in?).and_call_original

    # Stub recaptcha ENV vars to prevent errors in views
    stub_const("ENV", ENV.to_hash.merge("RECAPTCHA_SITE_KEY" => "test_site_key"))
  end

  let(:user) { create(:user, email: "test@example.com", name: "Test User") }

  describe "GET /login" do
    it "returns 200" do
      get login_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the login form" do
      get login_path
      expect(response.body).to include("Send login link")
      expect(response.body).to include("email")
    end
  end

  describe "POST /login" do
    context "with a registered email" do
      it "sends a magic link email" do
        expect {
          post login_path, params: { email: user.email }
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
      end

      it "redirects to email_sent page" do
        post login_path, params: { email: user.email }
        expect(response).to redirect_to(email_sent_path)
      end
    end

    context "with an unregistered email" do
      it "shows the same redirect to prevent enumeration" do
        post login_path, params: { email: "nobody@example.com" }
        expect(response).to redirect_to(email_sent_path)
      end

      it "creates the user and sends an email (self-registration)" do
        expect {
          post login_path, params: { email: "nobody@example.com" }
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
          .and change { User.count }.by(1)
      end
    end

    context "a bot submits addresses it does not own (the POST is unauthenticated)" do
      let!(:property) { create(:property) }

      it "grants no property access and creates no visitor, so members never see junk visitors" do
        expect {
          post login_path, params: { email: "stranger@example.com" }
        }.to change(PropertyUser, :count).by(0)
          .and change(Visitor, :count).by(0)

        expect(User.find_by(email: "stranger@example.com").properties).to be_empty
      end
    end

    context "a script hammers the login form to mail-bomb one inbox" do
      it "stops sending after 3 links per address within 10 minutes" do
        expect {
          4.times { post login_path, params: { email: user.email } }
        }.to change { ActionMailer::Base.deliveries.count }.by(3)

        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to eq(I18n.t("sessions.throttled"))
      end
    end

    context "several people submit the form with an empty e-mail field" do
      it "does not lump them into one shared per-address bucket, so strangers cannot lock each other out" do
        3.times { post login_path, params: { email: "" }, env: { "REMOTE_ADDR" => "203.0.113.1" } }

        post login_path, params: { email: "" }, env: { "REMOTE_ADDR" => "203.0.113.2" }
        expect(response).to redirect_to(email_sent_path)
      end
    end

    context "a script registers many addresses from one IP" do
      it "stops after 10 submissions within 10 minutes, protecting the SMTP quota" do
        expect {
          11.times { |i| post login_path, params: { email: "bot#{i}@example.com" } }
        }.to change { ActionMailer::Base.deliveries.count }.by(10)

        expect(flash[:alert]).to eq(I18n.t("sessions.throttled"))
      end
    end

    context "the request arrives with a forged Host / X-Forwarded-Host header" do
      around do |example|
        original = Rails.configuration.x.app_hosts
        Rails.configuration.x.app_hosts = [ "tymlova.kopernici.cz" ]
        example.run
      ensure
        Rails.configuration.x.app_hosts = original
      end

      it "builds the emailed link on the default host, so the token never goes to the attacker's domain" do
        host! "evil.example"
        post login_path, params: { email: user.email }

        body = ActionMailer::Base.deliveries.last.body.encoded
        expect(body).not_to include("evil.example")
        expect(body).to include("example.com/auth/")
      end

      it "keeps the link on an allowlisted host, so tymlova users stay on tymlova" do
        host! "tymlova.kopernici.cz"
        post login_path, params: { email: user.email }

        expect(ActionMailer::Base.deliveries.last.body.encoded).to include("tymlova.kopernici.cz/auth/")
      end
    end

    context "with extra whitespace and uppercase email" do
      it "normalizes the email and sends" do
        user # ensure created with test@example.com
        expect {
          post login_path, params: { email: "  Test@Example.COM  " }
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
      end
    end
  end

  describe "GET /auth/:token (the link in the email)" do
    context "a mail scanner or link previewer fetches the link before the user clicks it" do
      it "shows a confirmation page without logging anyone in" do
        get auth_verify_path(token: GenerateMagicLinkToken.run!(user: user))

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.confirm.submit"))
        expect(session[:user_id]).to be_nil
      end

      it "leaves the link usable, so the user's real click still logs them in" do
        token = GenerateMagicLinkToken.run!(user: user)
        2.times { get auth_verify_path(token: token) }

        post auth_verify_path(token: token)
        expect(response).to redirect_to(root_path)
        expect(session[:user_id]).to eq(user.id)
      end
    end

    context "the link was already used or has expired" do
      it "sends the user back to login right away instead of offering a button that cannot work" do
        token = GenerateMagicLinkToken.run!(user: user)
        post auth_verify_path(token: token)
        reset!

        get auth_verify_path(token: token)
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include("Invalid or expired link")
      end
    end
  end

  describe "POST /auth/:token (confirming the login)" do
    context "with a valid token" do
      let(:token) { GenerateMagicLinkToken.run!(user: user) }

      it "creates a session and redirects to root" do
        post auth_verify_path(token: token)
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("Login successful")
      end
    end

    context "with an expired token" do
      let(:expired_token) do
        verifier = Rails.application.message_verifier("magic_link")
        payload = { user_id: user.id, exp: 1.hour.ago.to_i }
        verifier.generate(payload, purpose: :magic_link)
      end

      it "redirects to login with an error" do
        post auth_verify_path(token: expired_token)
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include("Invalid or expired link")
      end
    end

    context "with an invalid token" do
      it "redirects to login with an error" do
        post auth_verify_path(token: "garbage")
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include("Invalid or expired link")
      end
    end

    context "the link is opened again after it was used (browser history on a shared phone)" do
      it "refuses the second login" do
        token = GenerateMagicLinkToken.run!(user: user)
        post auth_verify_path(token: token)
        reset!

        post auth_verify_path(token: token)
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include("Invalid or expired link")
      end
    end

    context "the user logged out while an unused link was still in their inbox" do
      it "refuses that link, because logout revokes outstanding links" do
        login_token = GenerateMagicLinkToken.run!(user: user)
        post auth_verify_path(token: login_token)

        # A second link requested from another device, never clicked.
        leaked_token = GenerateMagicLinkToken.run!(user: user.reload)
        delete logout_path

        post auth_verify_path(token: leaked_token)
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include("Invalid or expired link")
      end
    end

    context "an admin removed an onboarded member from every property" do
      let!(:property) { create(:property) }

      it "does not re-grant access on the member's next login" do
        user.properties << property
        user.properties.delete(property)

        post auth_verify_path(token: GenerateMagicLinkToken.run!(user: user))

        expect(response).to redirect_to(root_path)
        expect(user.reload.properties).to be_empty
      end
    end

    context "a brand-new user verifies their email and enters their name" do
      let!(:property) { create(:property) }

      it "gets the default property and a visitor named after them, not after their email" do
        post login_path, params: { email: "jan@example.com" }
        new_user = User.find_by!(email: "jan@example.com")

        post auth_verify_path(token: GenerateMagicLinkToken.run!(user: new_user))
        expect(response).to redirect_to(onboarding_path)

        patch onboarding_path, params: { name: "Jan" }
        expect(response).to redirect_to(root_path)

        new_user.reload
        expect(new_user.properties).to eq([ property ])
        expect(new_user.default_visitor.name).to eq("Jan")
        expect(property.visitors.pluck(:name)).not_to include("jan@example.com")
      end
    end
  end

  describe "SMS login" do
    let(:phone_user) { create(:user, :phone_only) }

    before do
      allow_any_instance_of(SessionsController).to receive(:verify_recaptcha).and_return(true)
      allow_any_instance_of(SessionsController).to receive(:recaptcha_reply).and_return(nil)
      allow(SendSmsMessage).to receive(:run)
    end

    def request_code
      post login_sms_path, params: { phone_number: phone_user.phone_number }
      phone_user.reload.sms_otp_code
    end

    context "an attacker who knows the victim's number guesses OTP codes" do
      it "kills the code after 5 wrong guesses, so even the right code no longer logs in" do
        code = request_code
        wrong = code == "000000" ? "111111" : "000000"

        5.times { post verify_otp_path, params: { code: wrong } }
        post verify_otp_path, params: { code: code }

        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to eq(I18n.t("sessions.sms.too_many_attempts"))
        expect(session[:user_id]).to be_nil
      end

      it "throttles verification requests from one IP" do
        request_code
        11.times { post verify_otp_path, params: { code: "000000" } }

        expect(flash[:alert]).to eq(I18n.t("sessions.throttled"))
      end
    end

    context "the user mistypes once and then enters the right code" do
      it "logs them in" do
        code = request_code
        wrong = code == "000000" ? "111111" : "000000"

        post verify_otp_path, params: { code: wrong }
        post verify_otp_path, params: { code: code }

        expect(session[:user_id]).to eq(phone_user.id)
      end
    end

    context "a script keeps requesting SMS codes (each SMS costs money)" do
      it "throttles after 5 requests from one IP within 10 minutes" do
        6.times { post login_sms_path, params: { phone_number: phone_user.phone_number } }

        expect(SendSmsMessage).to have_received(:run).exactly(5).times
        expect(flash[:alert]).to eq(I18n.t("sessions.throttled"))
      end
    end
  end

  describe "flash messages on the login page" do
    it "shows the logout notice once (as a toast), not twice" do
      post auth_verify_path(token: GenerateMagicLinkToken.run!(user: user))
      delete logout_path
      follow_redirect!

      expect(response.body.scan(I18n.t("sessions.destroy.notice")).size).to eq(1)
    end
  end

  describe "DELETE /logout" do
    it "clears the session and redirects to login" do
      # First log in via the real flow
      token = GenerateMagicLinkToken.run!(user: user)
      post auth_verify_path(token: token)

      # Now logout
      delete logout_path
      expect(response).to redirect_to(login_path)
      expect(flash[:notice]).to include("Logged out successfully")
    end
  end
end
