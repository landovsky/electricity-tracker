# frozen_string_literal: true

# Verifies a magic link token and returns the associated user.
#
# Decodes the signed token, checks expiration, and looks up the user.
# Returns nil (via errors) if the token is invalid, expired, already used,
# or the user is not found / soft-deleted.
#
# A successful verification consumes the user's magic_link_nonce, so the same
# link cannot log anyone in a second time (e.g. from browser history or a
# forwarded email).
#
# @example
#   outcome = VerifyMagicLinkToken.run(token: "eyJfcmFpbHMi...")
#   outcome.result # => #<User id: 1, ...> or nil
class VerifyMagicLinkToken < ActiveInteraction::Base
  string :token

  validates :token, presence: true

  def execute
    payload = decode_token
    return nil unless payload

    user = find_user(payload["user_id"])
    return nil unless user

    if expired?(payload["exp"])
      errors.add(:token, "has expired")
      return nil
    end

    unless consume_nonce!(user, payload["nonce"])
      errors.add(:token, "is invalid")
      return nil
    end

    user
  end

  private

  def decode_token
    verifier.verify(token, purpose: :magic_link)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    errors.add(:token, "is invalid")
    nil
  end

  def find_user(user_id)
    user = User.kept.find_by(id: user_id)
    errors.add(:token, "is invalid") unless user
    user
  end

  # Atomic compare-and-clear: only one request can consume a given nonce,
  # even when the same link is opened twice concurrently.
  def consume_nonce!(user, nonce)
    return false if nonce.blank?

    User.where(id: user.id, magic_link_nonce: nonce.to_s).update_all(magic_link_nonce: nil) == 1
  end

  def expired?(exp)
    Time.current.to_i > exp
  end

  def verifier
    Rails.application.message_verifier("magic_link")
  end
end
