class MeterReading < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Associations
  belongs_to :meter_reading_event
  belongs_to :meter

  # Validations
  validates :value_kwh, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :monotonically_non_decreasing

  # Readings that still count: neither the reading nor its event is soft-deleted.
  # Older delete code discarded only the event, so filtering on the event is what
  # keeps a deleted typo from staying the "last reading" (C1 checks, C5 defaults,
  # dashboard hints, OCR reference).
  scope :live, -> { kept.joins(:meter_reading_event).merge(MeterReadingEvent.kept) }

  private

  # C1: Meter readings are monotonically non-decreasing
  def monotonically_non_decreasing
    return unless meter && value_kwh.present?

    # Find the most recent reading for the same meter
    previous_reading = MeterReading.live
                                   .where(meter_id: meter_id)
                                   .where.not(id: id)
                                   .order("meter_reading_events.recorded_at DESC")
                                   .first

    if previous_reading && value_kwh < previous_reading.value_kwh
      errors.add(:value_kwh, :not_monotonic, value: previous_reading.value_kwh)
    end
  end
end
