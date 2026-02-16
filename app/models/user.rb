class User < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Enums
  enum :role, { member: "member", admin: "admin" }, validate: true

  # Associations
  has_many :meter_reading_events, foreign_key: :recorded_by_user_id, dependent: :nullify
  has_many :manual_consumption_entries, foreign_key: :recorded_by_user_id, dependent: :nullify

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true
end
