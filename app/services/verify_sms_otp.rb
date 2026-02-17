# frozen_string_literal: true

# Verifies a 6-digit SMS OTP code for a user.
# The code must match and not be older than 5 minutes.
# On success, clears the stored OTP and returns the user.
class VerifySmsOtp < ApplicationService
  object :user, class: User
  string :code

  validates :user, presence: true
  validates :code, presence: true

  OTP_EXPIRY = 5.minutes

  def execute
    if user.sms_otp_code.blank?
      errors.add(:code, :invalid)
      return nil
    end

    if user.sms_otp_sent_at.blank? || user.sms_otp_sent_at < OTP_EXPIRY.ago
      clear_otp!
      errors.add(:code, :expired)
      return nil
    end

    unless ActiveSupport::SecurityUtils.secure_compare(code, user.sms_otp_code)
      errors.add(:code, :invalid)
      return nil
    end

    clear_otp!
    user
  end

  private

  def clear_otp!
    user.update!(sms_otp_code: nil, sms_otp_sent_at: nil)
  end
end
