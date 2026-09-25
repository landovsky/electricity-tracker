# frozen_string_literal: true

# Service to record a standalone meter reading for a meter_only property.
#
# Used for properties that only track meter state over time (e.g., gas meters)
# without visitor check-in/check-out workflows.
#
# Creates a MeterReadingEvent (type: periodic) with associated MeterReadings.
# No Stay is created.
#
# Returns the created MeterReadingEvent on success.
class RecordMeterReading < ApplicationService
  object :property, class: Property
  object :recorded_by_user, class: User
  time :recorded_at, default: -> { Time.current }
  hash :meter_readings, strip: false
  string :note, default: nil

  validate :validate_meter_only_property
  validate :validate_at_least_one_reading
  validate :validate_chronological_consistency
  # C1 is checked for every meter before anything is written, so a reading
  # below the previous one never leaves a partial event behind.
  validate :validate_monotonic_readings

  def execute
    ActiveRecord::Base.transaction do
      event = MeterReadingEvent.create!(
        event_type: :periodic,
        recorded_at: recorded_at,
        recorded_by_user: recorded_by_user,
        note: note
      )

      meter_readings.each do |meter_id, value|
        next if value.blank?

        meter = property.meters.kept.find(meter_id)

        MeterReading.create!(
          meter_reading_event: event,
          meter: meter,
          value_kwh: value.to_d
        )
      end

      event
    end
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.join(", "))
    nil
  end

  private

  def validate_meter_only_property
    return if property&.meter_only?

    errors.add(:base, I18n.t("services.record_meter_reading.not_meter_only"))
  end

  def validate_at_least_one_reading
    return if meter_readings&.values&.any?(&:present?)

    errors.add(:base, I18n.t("services.record_meter_reading.no_readings"))
  end

  def validate_chronological_consistency
    return unless recorded_at.present? && property.present?

    last_event = MeterReadingEvent.kept
                   .joins(meter_readings: :meter)
                   .where(meters: { property_id: property.id })
                   .order(recorded_at: :desc)
                   .first

    return unless last_event

    if recorded_at < last_event.recorded_at
      errors.add(:recorded_at, I18n.t("services.record_meter_reading.not_chronological",
                                       timestamp: I18n.l(last_event.recorded_at)))
    end
  end

  def validate_monotonic_readings
    return unless property && meter_readings

    meter_readings.each do |meter_id, value|
      next if value.blank?

      meter = property.meters.kept.find_by(id: meter_id)
      validate_monotonic_reading(meter, value.to_d) if meter
    end
  end

  def validate_monotonic_reading(meter, new_value)
    last_reading = meter.last_reading
    return unless last_reading

    if new_value < last_reading.value_kwh
      errors.add(:base, I18n.t("services.record_meter_reading.not_monotonic",
                                 label: meter.label,
                                 new_value: new_value,
                                 last_value: last_reading.value_kwh))
    end
  end
end
