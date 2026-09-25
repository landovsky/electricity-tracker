# frozen_string_literal: true

# Finds an existing user by email or creates a new one for self-registration.
# New users are created with role :member and blank name (filled during onboarding).
#
# This runs on an unauthenticated POST, before the person has proven they own
# the address/number, so it only creates a bare User. Property access (and the
# Visitor that comes with it) is granted in OnboardingController once the login
# has been verified and a name entered.
class FindOrCreateUserByEmail < ApplicationService
  string :email

  validates :email, presence: true

  def execute
    normalized = email.strip.downcase
    user = User.kept.find_by(email: normalized)
    return user if user

    User.create!(email: normalized, name: nil, role: :member)
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.join(", "))
    nil
  end
end
