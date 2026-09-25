# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerifySmsOtp, type: :service do
  let(:user) { create(:user, :with_phone) }
  let!(:code) { GenerateSmsOtp.run!(user: user) }

  def wrong_code
    code == "000000" ? "111111" : "000000"
  end

  context "the user types the code from the SMS" do
    it "logs them in and burns the code so it cannot be replayed" do
      outcome = described_class.run(user: user, code: code)

      expect(outcome.result).to eq(user)
      expect(user.reload.sms_otp_code).to be_nil
    end
  end

  context "the user mistypes the code a couple of times" do
    it "still accepts the right code, so a typo does not force a new SMS" do
      2.times { described_class.run(user: user, code: wrong_code) }

      expect(described_class.run(user: user, code: code).result).to eq(user)
    end
  end

  context "someone brute-forces the 6-digit code space" do
    it "destroys the code after #{described_class::MAX_ATTEMPTS} attempts, so the right code no longer works" do
      described_class::MAX_ATTEMPTS.times { described_class.run(user: user, code: wrong_code) }

      outcome = described_class.run(user: user, code: code)

      expect(outcome.result).to be_nil
      expect(outcome.errors.added?(:code, :too_many_attempts)).to be(true)
      expect(user.reload.sms_otp_code).to be_nil
    end

    it "counts attempts in the database, so parallel requests with stale user objects share one budget" do
      stale_copies = Array.new(described_class::MAX_ATTEMPTS) { User.find(user.id) }
      stale_copies.each { |copy| described_class.run(user: copy, code: wrong_code) }

      expect(described_class.run(user: User.find(user.id), code: code).result).to be_nil
    end
  end

  context "the user requests a fresh SMS after exhausting the attempts" do
    it "gives the new code a full attempt budget" do
      described_class::MAX_ATTEMPTS.times { described_class.run(user: user, code: wrong_code) }
      described_class.run(user: user, code: wrong_code)

      new_code = GenerateSmsOtp.run!(user: user.reload)

      expect(described_class.run(user: user, code: new_code).result).to eq(user)
    end
  end
end
