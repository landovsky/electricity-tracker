# frozen_string_literal: true

# Service to check in a visitor to a property.
#
# Creates a MeterReadingEvent with meter readings and opens a new Stay.
#
# Enforces constraints:
# - C1: Meter readings are monotonically non-decreasing
# - C2: A visitor can have at most one open stay at a time
# - C4: Main meter reading is required
# - C5: Secondary meter reading is optional (defaults to last known value)
# - C6: Chronological consistency
#
# Accepts meter readings in two ways:
# 1. Dynamic: meter_readings hash { meter_id => value_kwh }
# 2. Legacy: main_meter_reading / secondary_meter_reading params
#
# Returns the created Stay on success, or adds errors to the service errors collection.
class CheckInVisitor < ApplicationService
  # Inputs
  object :visitor, class: Visitor
  object :property, class: Property
  object :recorded_by_user, class: User
  time :recorded_at, default: -> { Time.current }
  decimal :main_meter_reading, default: nil
  decimal :secondary_meter_reading, default: nil
  hash :meter_readings, strip: false, default: nil
  string :note, default: nil

  # Custom validations
  validate :validate_visitors_tracking_mode
  validate :validate_main_reading_provided
  validate :validate_no_open_stay
  validate :validate_chronological_consistency

  def execute
    # Create everything in a transaction
    ActiveRecord::Base.transaction do
      # Create the meter reading event
      event = create_meter_reading_event!

      # Create meter readings
      create_meter_readings!(event)

      # Create the stay
      create_stay!(event)
    end
  rescue ActiveRecord::RecordInvalid => e
    # Add validation errors from any failed record
    errors.add(:base, e.record.errors.full_messages.join(", "))
    nil
  rescue StandardError => e
    # Log unexpected errors and add to service errors
    Rails.logger.error("CheckInVisitor failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    errors.add(:base, "Failed to check in visitor: #{e.message}")
    nil
  end

  private

  # C4: At least one main reading must be provided
  def validate_main_reading_provided
    if meter_readings.present?
      # Dynamic path: verify that a main meter is included in the hash with a value
      main_meters = property&.meters&.kept&.where(meter_type: :main)
      has_main = main_meters&.any? { |m| meter_readings[m.id.to_s].present? || meter_readings[m.id].present? }
      errors.add(:main_meter_reading, :blank) unless has_main
      return
    end

    return if main_meter_reading.present?

    errors.add(:main_meter_reading, :blank)
  end

  # C2: Validate visitor has no open stay
  def validate_no_open_stay
    return unless visitor.present?

    if visitor.stays.kept.open.exists?
      errors.add(:visitor, I18n.t("services.check_in_visitor.visitor_has_open_stay"))
    end
  end

  # C6: Validate chronological consistency
  def validate_chronological_consistency
    return unless recorded_at.present?

    last_event = MeterReadingEvent.kept
                                   .joins(meter_readings: :meter)
                                   .where(meters: { property_id: property.id })
                                   .order(recorded_at: :desc)
                                   .first

    return unless last_event

    if recorded_at < last_event.recorded_at
      errors.add(:recorded_at, I18n.t("services.check_in_visitor.not_chronological", timestamp: I18n.l(last_event.recorded_at)))
    end
  end

  def create_meter_reading_event!
    MeterReadingEvent.create!(
      event_type: :check_in,
      recorded_at: recorded_at,
      recorded_by_user: recorded_by_user,
      note: note
    )
  end

  def create_meter_readings!(event)
    readings = resolved_meter_readings

    readings.each do |meter, value|
      MeterReading.create!(
        meter_reading_event: event,
        meter: meter,
        value_kwh: value
      )
    end
  end

  # Resolve meter readings from either the dynamic hash or legacy params.
  # For secondary/optional meters without a provided value, default to last known reading.
  def resolved_meter_readings
    readings = {}

    if meter_readings.present?
      # Dynamic path: { meter_id => value_kwh }
      meter_readings.each do |meter_id, value|
        meter = property.meters.kept.find(meter_id)
        readings[meter] = value.to_d if value.present?
      end
    else
      # Legacy path: main_meter_reading / secondary_meter_reading
      main_meter = property.meters.kept.find_by!(meter_type: :main)
      readings[main_meter] = main_meter_reading if main_meter_reading.present?

      secondary_meter = property.meters.kept.find_by(meter_type: :secondary)
      if secondary_meter
        if secondary_meter_reading.present?
          readings[secondary_meter] = secondary_meter_reading
        else
          last_value = secondary_meter.last_reading&.value_kwh
          readings[secondary_meter] = last_value if last_value
        end
      end
    end

    # C5: For non-main meters without a provided value, default to last known reading
    property.meters.kept.secondary.each do |meter|
      next if readings.key?(meter)

      last_value = meter.last_reading&.value_kwh
      readings[meter] = last_value if last_value
    end

    readings
  end

  def validate_visitors_tracking_mode
    return if property&.visitors?

    errors.add(:base, I18n.t("services.check_in_visitor.not_visitors_mode"))
  end

  def create_stay!(event)
    Stay.create!(
      visitor: visitor,
      property: property,
      check_in_event: event,
      note: note
    )
  end
end
