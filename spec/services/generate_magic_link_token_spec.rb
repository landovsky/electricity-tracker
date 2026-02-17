# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateMagicLinkToken, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe ".run" do
    context "with a valid user" do
      it "returns a token string" do
        outcome = described_class.run(user: user)

        expect(outcome).to be_valid
        expect(outcome.result).to be_a(String)
        expect(outcome.result).to be_present
      end

      it "generates a token that can be verified" do
        token = described_class.run!(user: user)
        verifier = Rails.application.message_verifier("magic_link")
        payload = verifier.verify(token, purpose: :magic_link)

        expect(payload["user_id"]).to eq(user.id)
        expect(payload["exp"]).to be > Time.current.to_i
      end

      it "sets expiration to 15 minutes from now" do
        travel_to Time.current do
          token = described_class.run!(user: user)
          verifier = Rails.application.message_verifier("magic_link")
          payload = verifier.verify(token, purpose: :magic_link)

          expect(payload["exp"]).to eq(15.minutes.from_now.to_i)
        end
      end
    end

    context "without a user" do
      it "is invalid" do
        outcome = described_class.run(user: nil)
        expect(outcome).not_to be_valid
      end
    end
  end
end
