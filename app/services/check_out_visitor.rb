# frozen_string_literal: true

# Service to check out a visitor from a property.
#
# This service handles UC2 (Visitor Check-out) from the specification.
# It records meter readings, validates constraints C1 and C3, closes the stay,
# and handles edge cases E3 (same-day check-in/out) and E8 (optional secondary meter).
#
# Accepts meter readings in two ways:
# 1. Dynamic: meter_readings hash { meter_id => value_kwh }
# 2. Legacy: main_meter_reading / secondary_meter_reading params
class CheckOutVisitor < ApplicationService
  # Inputs - either visitor or stay must be provided
  object :visitor, class: Visitor, default: nil
  object :stay, class: Stay, default: nil
  object :property, class: Property
  time :recorded_at, default: -> { Time.current }
  object :recorded_by_user, class: User
  float :main_meter_reading, default: nil
  float :secondary_meter_reading, default: nil
  hash :meter_readings, strip: false, default: nil
  string :note, default: nil

  validates :property, presence: true
  validates :recorded_by_user, presence: true
  validate :validate_main_reading_provided
  validate :visitor_or_stay_provided
  validate :stay_exists_and_is_open

  def execute
    ActiveRecord::Base.transaction do
      # Find or use the provided stay
      @stay = find_open_stay

      # Verify at least one main meter exists when using legacy params
      if meter_readings.blank?
        main_meter = property.meters.kept.find_by(meter_type: "main")
        errors.add(:base, "Main meter not found for property") and return unless main_meter
      end

      # Resolve readings
      readings = resolved_meter_readings

      # Validate meter readings against constraints
      validate_all_meter_readings(readings)
      return if errors.any?

      # Create check-out meter reading event
      check_out_event = MeterReadingEvent.create!(
        event_type: :check_out,
        recorded_at: recorded_at,
        recorded_by_user: recorded_by_user,
        note: note
      )

      # Create meter readings
      readings.each do |meter, value|
        MeterReading.create!(
          meter_reading_event: check_out_event,
          meter: meter,
          value_kwh: value
        )
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

  def validate_main_reading_provided
    # At least one main reading must be provided via either path
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

  # Resolve meter readings from either the dynamic hash or legacy params.
  def resolved_meter_readings
    readings = {}

    if meter_readings.present?
      # Dynamic path: { meter_id => value_kwh }
      meter_readings.each do |meter_id, value|
        meter = property.meters.kept.find(meter_id)
        readings[meter] = value.to_f if value.present?
      end
    else
      # Legacy path
      main_meter = property.meters.kept.find_by(meter_type: "main")
      if main_meter && main_meter_reading.present?
        readings[main_meter] = main_meter_reading
      end

      secondary_meter = property.meters.kept.find_by(meter_type: "secondary")
      if secondary_meter
        if secondary_meter_reading.present?
          readings[secondary_meter] = secondary_meter_reading
        else
          # E8: Default to last known value
          last_reading = find_last_meter_reading(secondary_meter)
          readings[secondary_meter] = last_reading.value_kwh if last_reading
        end
      end
    end

    # For non-main meters without a provided value, default to last known reading
    property.meters.kept.secondary.each do |meter|
      next if readings.key?(meter)

      last_reading = find_last_meter_reading(meter)
      readings[meter] = last_reading.value_kwh if last_reading
    end

    readings
  end

  def validate_all_meter_readings(readings)
    readings.each do |meter, value|
      # C1: Meter readings are monotonically non-decreasing
      validate_monotonic_reading(meter, value, meter.label)

      # C3: Check-out reading >= check-in reading (per meter)
      validate_checkout_gte_checkin(meter, value, meter.label)
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
