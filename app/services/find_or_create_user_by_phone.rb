# frozen_string_literal: true

# Finds an existing user by phone number or creates a new one for self-registration.
# New users are created with role :member and blank name (filled during onboarding).
class FindOrCreateUserByPhone < ApplicationService
  string :phone_number

  validates :phone_number, presence: true

  def execute
    normalized = normalize_phone(phone_number.strip)

    unless normalized.match?(/\A\+420\d{9}\z/)
      errors.add(:phone_number, :invalid)
      return nil
    end

    user = User.kept.find_by(phone_number: normalized)
    return user if user

    User.create!(phone_number: normalized, name: nil, role: :member)
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.join(", "))
    nil
  end

  private

  # Normalize Czech phone numbers: accept "777123456" or "00420777123456" → "+420777123456"
  def normalize_phone(phone)
    digits = phone.gsub(/[\s\-()]/, "")
    if digits.match?(/\A\d{9}\z/)
      "+420#{digits}"
    elsif digits.match?(/\A00420\d{9}\z/)
      "+#{digits[2..]}"
    else
      digits
    end
  end
end
