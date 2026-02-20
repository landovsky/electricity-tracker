# frozen_string_literal: true

# Finds an existing user by email or creates a new one for self-registration.
# New users are created with role :member and blank name (filled during onboarding).
class FindOrCreateUserByEmail < ApplicationService
  string :email

  validates :email, presence: true

  def execute
    normalized = email.strip.downcase
    user = User.kept.find_by(email: normalized)
    return user if user

    user = User.create!(email: normalized, name: nil, role: :member)
    AssignDefaultProperty.run!(user: user)
    user
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.join(", "))
    nil
  end
end
