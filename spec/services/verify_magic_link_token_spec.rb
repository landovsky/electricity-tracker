# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerifyMagicLinkToken, type: :service do
  let(:user) { create(:user) }

  def generate_token(user, expires_in: 15.minutes)
    verifier = Rails.application.message_verifier("magic_link")
    payload = { user_id: user.id, exp: expires_in.from_now.to_i }
    verifier.generate(payload, purpose: :magic_link)
  end

  describe ".run" do
    context "with a valid token" do
      it "returns the user" do
        token = generate_token(user)
        outcome = described_class.run(token: token)

        expect(outcome).to be_valid
        expect(outcome.result).to eq(user)
      end
    end

    context "with an expired token" do
      it "returns nil with an error" do
        token = generate_token(user, expires_in: -1.minute)
        outcome = described_class.run(token: token)

        expect(outcome.result).to be_nil
        expect(outcome.errors[:token]).to include("has expired")
      end
    end

    context "with a tampered token" do
      it "returns nil with an error" do
        outcome = described_class.run(token: "tampered-garbage-token")

        expect(outcome.result).to be_nil
        expect(outcome.errors[:token]).to include("is invalid")
      end
    end

    context "with a blank token" do
      it "is invalid" do
        outcome = described_class.run(token: "")
        expect(outcome).not_to be_valid
      end
    end

    context "when the user has been soft-deleted" do
      it "returns nil" do
        token = generate_token(user)
        user.discard

        outcome = described_class.run(token: token)
        expect(outcome.result).to be_nil
        expect(outcome.errors[:token]).to include("is invalid")
      end
    end

    context "when the user no longer exists" do
      it "returns nil" do
        token = generate_token(user)
        user.destroy!

        outcome = described_class.run(token: token)
        expect(outcome.result).to be_nil
      end
    end
  end
end
