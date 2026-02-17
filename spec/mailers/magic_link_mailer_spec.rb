# frozen_string_literal: true

require "rails_helper"

RSpec.describe MagicLinkMailer, type: :mailer do
  let(:user) { create(:user, email: "petr@example.com", name: "Petr") }
  let(:token) { "test-magic-token-123" }

  describe "#login_link" do
    subject(:mail) { described_class.login_link(user: user, token: token) }

    it "sends to the user's email" do
      expect(mail.to).to eq([ "petr@example.com" ])
    end

    it "has the correct subject" do
      expect(mail.subject).to eq("Your login link — Electricity Tracker")
    end

    it "includes the login link in the HTML body" do
      expect(mail.body.encoded).to include("/auth/test-magic-token-123")
    end

    it "includes the user's name" do
      expect(mail.body.encoded).to include("Petr")
    end

    it "mentions the expiration time" do
      expect(mail.body.encoded).to include("15 minutes")
    end

    it "has both HTML and text parts" do
      expect(mail.parts.map(&:content_type)).to include(
        a_string_matching("text/html"),
        a_string_matching("text/plain")
      )
    end
  end
end
