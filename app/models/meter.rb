class Meter < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Enums
  enum :meter_type, { main: "main", secondary: "secondary" }, validate: true

  # Associations
  belongs_to :property
  has_many :meter_readings, dependent: :destroy

  # Validations
  validates :meter_type, presence: true
  validates :label, presence: true
  validates :unit, presence: true
  validates :meter_type, uniqueness: { scope: :property_id }

  # Scopes
  scope :main, -> { where(meter_type: "main") }
  scope :secondary, -> { where(meter_type: "secondary") }
end
