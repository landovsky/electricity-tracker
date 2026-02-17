# frozen_string_literal: true

# Generates a signed, time-limited token for magic link authentication.
#
# Uses Rails MessageVerifier to create tokens containing the user ID
# and expiration timestamp. Tokens are signed with the app's secret_key_base.
#
# @example
#   outcome = GenerateMagicLinkToken.run!(user: user)
#   # => "eyJfcmFpbHMi..."
class GenerateMagicLinkToken < ActiveInteraction::Base
  object :user, class: User

  validates :user, presence: true

  def execute
    verifier.generate(payload, purpose: :magic_link)
  end

  private

  def payload
    { user_id: user.id, exp: 15.minutes.from_now.to_i }
  end

  def verifier
    Rails.application.message_verifier("magic_link")
  end
end
