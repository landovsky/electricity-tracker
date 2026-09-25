# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerifyMagicLinkToken, type: :service do
  let(:user) { create(:user) }

  def generate_token(user, expires_in: 15.minutes, nonce: nil)
    user.update_column(:magic_link_nonce, "nonce-#{user.id}") if user.magic_link_nonce.blank?
    verifier = Rails.application.message_verifier("magic_link")
    payload = { user_id: user.id, nonce: nonce || user.magic_link_nonce, exp: expires_in.from_now.to_i }
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

    context "a login link leaks after it was used (browser history, forwarded email)" do
      it "refuses the second use, so the link cannot open another session" do
        token = generate_token(user)

        expect(described_class.run(token: token).result).to eq(user)

        second = described_class.run(token: token)
        expect(second.result).to be_nil
        expect(second.errors[:token]).to include("is invalid")
      end
    end

    context "the user logged out (nonce cleared) before an older link was opened" do
      it "refuses the link, because logout revokes every outstanding link" do
        token = generate_token(user)
        user.update_column(:magic_link_nonce, nil)

        expect(described_class.run(token: token).result).to be_nil
      end
    end

    context "a token signed before links carried a nonce" do
      it "is refused, so pre-upgrade links cannot bypass single use" do
        verifier = Rails.application.message_verifier("magic_link")
        token = verifier.generate({ user_id: user.id, exp: 15.minutes.from_now.to_i }, purpose: :magic_link)

        expect(described_class.run(token: token).result).to be_nil
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
