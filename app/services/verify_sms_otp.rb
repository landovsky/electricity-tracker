# frozen_string_literal: true

# Verifies a 6-digit SMS OTP code for a user.
# The code must match and not be older than 5 minutes.
# On success, clears the stored OTP and returns the user.
#
# Each code allows at most MAX_ATTEMPTS verification attempts. Once they are
# spent the code is destroyed and the user has to request a new one, so the
# 10^6 code space cannot be brute-forced within the expiry window.
class VerifySmsOtp < ApplicationService
  object :user, class: User
  string :code

  validates :user, presence: true
  validates :code, presence: true

  OTP_EXPIRY = 5.minutes
  MAX_ATTEMPTS = 5

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

    unless claim_attempt!
      clear_otp!
      errors.add(:code, :too_many_attempts)
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

  # Atomically spends one attempt. The conditional UPDATE keeps concurrent
  # guesses from exceeding MAX_ATTEMPTS even when they race each other.
  def claim_attempt!
    User.where(id: user.id)
      .where(sms_otp_attempts: ...MAX_ATTEMPTS)
      .update_all("sms_otp_attempts = sms_otp_attempts + 1") == 1
  end

  # update_columns always writes: the in-memory attempt counter is stale after
  # claim_attempt!, so a dirty-tracking update! could skip resetting it.
  def clear_otp!
    user.update_columns(sms_otp_code: nil, sms_otp_sent_at: nil, sms_otp_attempts: 0)
  end
end
