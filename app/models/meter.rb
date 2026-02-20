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
  validates :identifier, uniqueness: { scope: :property_id }, allow_blank: true

  # Scopes
  scope :main, -> { where(meter_type: "main") }
  scope :secondary, -> { where(meter_type: "secondary") }
  scope :grouped, ->(group) { where(meter_group: group) }

  # Returns the last recorded reading for this meter
  def last_reading
    meter_readings
      .kept
      .joins(:meter_reading_event)
      .order("meter_reading_events.recorded_at DESC")
      .first
  end
end
