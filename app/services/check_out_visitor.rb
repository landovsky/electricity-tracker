# frozen_string_literal: true

# Service to check out a visitor from a property.
#
# This service handles UC2 (Visitor Check-out) from the specification.
# It records meter readings, validates constraints C1 and C3, closes the stay,
# and handles edge cases E3 (same-day check-in/out) and E8 (optional secondary meter).
#
# Usage:
#   outcome = CheckOutVisitor.run(
#     visitor: visitor,
#     property: property,
#     recorded_at: Time.current,
#     recorded_by_user: user,
#     main_meter_reading: 1050.0,
#     secondary_meter_reading: 525.0, # optional
#     note: "Check out after weekend visit"
#   )
#
#   if outcome.valid?
#     closed_stay = outcome.result
#   else
#     outcome.errors
#   end
class CheckOutVisitor < ApplicationService
  # Inputs - either visitor or stay must be provided
  object :visitor, class: Visitor, default: nil
  object :stay, class: Stay, default: nil
  object :property, class: Property
  time :recorded_at, default: -> { Time.current }
  object :recorded_by_user, class: User
  float :main_meter_reading
  float :secondary_meter_reading, default: nil
  string :note, default: nil

  validates :property, presence: true
  validates :recorded_by_user, presence: true
  validates :main_meter_reading, presence: true
  validate :visitor_or_stay_provided
  validate :stay_exists_and_is_open

  def execute
    ActiveRecord::Base.transaction do
      # Find or use the provided stay
      @stay = find_open_stay

      # Get meters for the property
      main_meter = property.meters.kept.find_by(meter_type: "main")
      secondary_meter = property.meters.kept.find_by(meter_type: "secondary")

      errors.add(:base, "Main meter not found for property") and return unless main_meter

      # Validate meter readings against constraints
      validate_meter_readings(main_meter, secondary_meter)
      return if errors.any?

      # Create check-out meter reading event
      check_out_event = MeterReadingEvent.create!(
        event_type: :check_out,
        recorded_at: recorded_at,
        recorded_by_user: recorded_by_user,
        note: note
      )

      # Create meter readings
      MeterReading.create!(
        meter_reading_event: check_out_event,
        meter: main_meter,
        value_kwh: main_meter_reading
      )

      # E8: Secondary meter reading is optional
      if secondary_meter_reading.present? && secondary_meter.present?
        MeterReading.create!(
          meter_reading_event: check_out_event,
          meter: secondary_meter,
          value_kwh: secondary_meter_reading
        )
      elsif secondary_meter.present? && secondary_meter_reading.nil?
        # E8: If secondary meter reading not provided, default to last known value
        last_secondary_reading = find_last_meter_reading(secondary_meter)
        if last_secondary_reading
          MeterReading.create!(
            meter_reading_event: check_out_event,
            meter: secondary_meter,
            value_kwh: last_secondary_reading.value_kwh
          )
        end
      end

      # Close the stay by setting check_out_event_id
      @stay.update!(check_out_event: check_out_event)

      # Return the closed stay
      @stay
    end
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    nil
  end

  private

  def visitor_or_stay_provided
    if visitor.nil? && stay.nil?
      errors.add(:base, "Either visitor or stay must be provided")
    end
  end

  def stay_exists_and_is_open
    return if errors.any? # Skip if previous validations failed

    target_stay = stay || (visitor && property ? visitor.stays.kept.where(property: property).open.first : nil)

    if target_stay.nil?
      if visitor
        errors.add(:base, "Visitor #{visitor.name} does not have an open stay at #{property.name}")
      else
        errors.add(:base, "Stay not found")
      end
    elsif target_stay.closed?
      errors.add(:base, "Stay is already closed")
    end
  end

  def find_open_stay
    if stay.present?
      stay
    else
      visitor.stays.kept.where(property: property).open.first
    end
  end

  def validate_meter_readings(main_meter, secondary_meter)
    # C1: Meter readings are monotonically non-decreasing
    validate_monotonic_reading(main_meter, main_meter_reading, "Main meter")

    if secondary_meter_reading.present? && secondary_meter.present?
      validate_monotonic_reading(secondary_meter, secondary_meter_reading, "Secondary meter")
    end

    # C3: Check-out reading >= check-in reading (per meter)
    validate_checkout_gte_checkin(main_meter, main_meter_reading, "Main meter")

    if secondary_meter_reading.present? && secondary_meter.present?
      validate_checkout_gte_checkin(secondary_meter, secondary_meter_reading, "Secondary meter")
    end
  end

  def validate_monotonic_reading(meter, new_reading, label)
    last_reading = find_last_meter_reading(meter)
    return unless last_reading

    if new_reading < last_reading.value_kwh
      errors.add(
        :base,
        "#{label} reading (#{new_reading} kWh) must be greater than or equal to the previous reading (#{last_reading.value_kwh} kWh)"
      )
    end
  end

  def validate_checkout_gte_checkin(meter, new_reading, label)
    return unless @stay.check_in_event

    check_in_reading = @stay.check_in_event.meter_readings.kept.find_by(meter: meter)
    return unless check_in_reading

    if new_reading < check_in_reading.value_kwh
      errors.add(
        :base,
        "#{label} reading at check-out (#{new_reading} kWh) must be greater than or equal to check-in reading (#{check_in_reading.value_kwh} kWh)"
      )
    end
  end

  def find_last_meter_reading(meter)
    MeterReading.kept
                 .joins(:meter_reading_event)
                 .where(meter: meter)
                 .order("meter_reading_events.recorded_at DESC")
                 .first
  end
end
