class User < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Enums
  enum :role, { member: "member", admin: "admin" }, validate: true

  # Associations
  has_many :meter_reading_events, foreign_key: :recorded_by_user_id, dependent: :nullify
  has_many :manual_consumption_entries, foreign_key: :recorded_by_user_id, dependent: :nullify

  # Validations
  validates :email, uniqueness: true, allow_nil: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :email, presence: true, unless: :phone_number?
  validates :phone_number, uniqueness: true, allow_nil: true
  validates :phone_number, format: { with: /\A\+420\d{9}\z/ }, allow_blank: true
  validates :role, presence: true

  # A user is onboarded once they have set their name
  def onboarded?
    name.present?
  end
end
