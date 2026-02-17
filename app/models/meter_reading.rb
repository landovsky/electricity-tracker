class MeterReading < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Associations
  belongs_to :meter_reading_event
  belongs_to :meter

  # Validations
  validates :value_kwh, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :monotonically_non_decreasing

  private

  # C1: Meter readings are monotonically non-decreasing
  def monotonically_non_decreasing
    return unless meter && value_kwh.present?

    # Find the most recent reading for the same meter
    previous_reading = MeterReading.kept
                                   .joins(:meter_reading_event)
                                   .where(meter_id: meter_id)
                                   .where.not(id: id)
                                   .order("meter_reading_events.recorded_at DESC")
                                   .first

    if previous_reading && value_kwh < previous_reading.value_kwh
      errors.add(:value_kwh, :not_monotonic, value: previous_reading.value_kwh)
    end
  end
end
