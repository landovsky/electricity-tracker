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
# Returns the created Stay on success, or adds errors to the service errors collection.
class CheckInVisitor < ApplicationService
  # Inputs
  object :visitor, class: Visitor
  object :property, class: Property
  object :recorded_by_user, class: User
  time :recorded_at, default: -> { Time.current }
  decimal :main_meter_reading
  decimal :secondary_meter_reading, default: nil
  string :note, default: nil

  # Custom validations
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

  # C2: Validate visitor has no open stay
  def validate_no_open_stay
    return unless visitor.present?

    if visitor.stays.kept.open.exists?
      errors.add(:visitor, "already has an open stay")
    end
  end

  # C6: Validate chronological consistency
  # Note: MeterReadingEvent model has a validation for this, but it has a logic bug.
  # This service-level validation ensures the constraint is properly enforced.
  def validate_chronological_consistency
    return unless recorded_at.present?

    last_event = MeterReadingEvent.kept
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
    main_meter = property.meters.kept.find_by!(meter_type: :main)
    secondary_meter = property.meters.kept.find_by(meter_type: :secondary)

    # C4: Main meter reading is required
    MeterReading.create!(
      meter_reading_event: event,
      meter: main_meter,
      value_kwh: main_meter_reading
    )

    # C5: Secondary meter reading is optional
    if secondary_meter
      reading_value = secondary_meter_reading || last_secondary_reading(secondary_meter)

      if reading_value
        MeterReading.create!(
          meter_reading_event: event,
          meter: secondary_meter,
          value_kwh: reading_value
        )
      end
    end
  end

  def create_stay!(event)
    Stay.create!(
      visitor: visitor,
      property: property,
      check_in_event: event,
      note: note
    )
  end

  # Get the last known reading for the secondary meter
  def last_secondary_reading(meter)
    last_reading = meter.meter_readings
                        .kept
                        .joins(:meter_reading_event)
                        .order("meter_reading_events.recorded_at DESC")
                        .first

    last_reading&.value_kwh
  end
end
