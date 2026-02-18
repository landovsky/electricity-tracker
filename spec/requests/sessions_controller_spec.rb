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

    context "with extra whitespace and uppercase email" do
      it "normalizes the email and sends" do
        user # ensure created with test@example.com
        expect {
          post login_path, params: { email: "  Test@Example.COM  " }
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
      end
    end
  end

  describe "GET /auth/:token" do
    context "with a valid token" do
      let(:token) { GenerateMagicLinkToken.run!(user: user) }

      it "creates a session and redirects to root" do
        get auth_verify_path(token: token)
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
        get auth_verify_path(token: expired_token)
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include("Invalid or expired link")
      end
    end

    context "with an invalid token" do
      it "redirects to login with an error" do
        get auth_verify_path(token: "garbage")
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include("Invalid or expired link")
      end
    end
  end

  describe "DELETE /logout" do
    it "clears the session and redirects to login" do
      # First log in via the real flow
      token = GenerateMagicLinkToken.run!(user: user)
      get auth_verify_path(token: token)

      # Now logout
      delete logout_path
      expect(response).to redirect_to(login_path)
      expect(flash[:notice]).to include("Logged out successfully")
    end
  end
end
