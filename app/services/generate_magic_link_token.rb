# frozen_string_literal: true

# Generates a signed, time-limited token for magic link authentication.
#
# Uses Rails MessageVerifier to create tokens containing the user ID
# and expiration timestamp. Tokens are signed with the app's secret_key_base.
#
# The payload also carries the user's magic_link_nonce. VerifyMagicLinkToken
# clears the nonce on use (and logout clears it too), which makes every link
# single-use. The nonce is reused while it is set, so requesting a second link
# does not break the first one the user may already be clicking.
#
# @example
#   outcome = GenerateMagicLinkToken.run!(user: user)
#   # => "eyJfcmFpbHMi..."
class GenerateMagicLinkToken < ActiveInteraction::Base
  object :user, class: User

  validates :user, presence: true

  def execute
    user.update_column(:magic_link_nonce, SecureRandom.urlsafe_base64(24)) if user.magic_link_nonce.blank?
    verifier.generate(payload, purpose: :magic_link)
  end

  private

  def payload
    { user_id: user.id, nonce: user.magic_link_nonce, exp: 15.minutes.from_now.to_i }
  end

  def verifier
    Rails.application.message_verifier("magic_link")
  end
end
