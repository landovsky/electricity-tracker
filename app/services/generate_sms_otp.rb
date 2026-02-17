# frozen_string_literal: true

# Generates a 6-digit OTP code and stores it on the user record.
# The code expires after 5 minutes (checked by VerifySmsOtp).
class GenerateSmsOtp < ApplicationService
  object :user, class: User

  validates :user, presence: true

  def execute
    code = SecureRandom.random_number(10**6).to_s.rjust(6, "0")
    user.update!(sms_otp_code: code, sms_otp_sent_at: Time.current)
    code
  end
end
