class Visitor < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Enums
  enum :status, { active: "active", archived: "archived" }, validate: true

  # Associations
  has_many :stays, dependent: :destroy
  has_many :manual_consumption_entries, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :status, presence: true

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :archived, -> { where(status: "archived") }
end
