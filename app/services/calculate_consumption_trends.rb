# frozen_string_literal: true

# Service to calculate monthly consumption trends for meter_only properties.
#
# Instead of visitor-based allocation (CalculateConsumption), this computes
# monthly deltas from consecutive meter reading events, suitable for properties
# that only track meter readings without visitor check-in/check-out.
#
# Input:
#   - property: Property model instance
#   - start_date: Date
#   - end_date: Date
#
# Output:
#   {
#     months: [{ month: Date, total_kwh: Float, readings_count: Integer }, ...],
#     total_kwh: Float,
#     date_range: { start_date: Date, end_date: Date }
#   }
class CalculateConsumptionTrends < ApplicationService
  object :property, class: Property
  date :start_date
  date :end_date

  validate :validate_date_range

  def execute
    events = fetch_events
    return empty_result if events.size < 2

    deltas = compute_deltas(events)
    monthly = aggregate_by_month(deltas)

    {
      months: monthly,
      total_kwh: monthly.sum { |m| m[:total_kwh] }.round(2),
      date_range: { start_date: start_date, end_date: end_date }
    }
  end

  private

  def validate_date_range
    return unless start_date.present? && end_date.present?

    errors.add(:end_date, "must be after or equal to start_date") if end_date < start_date
  end

  def fetch_events
    # Include boundary event before range (for first delta)
    in_range = MeterReadingEvent.kept
                 .joins(meter_readings: :meter)
                 .where(meters: { property_id: property.id })
                 .where(recorded_at: start_date.beginning_of_day..end_date.end_of_day)
                 .distinct

    boundary_event = MeterReadingEvent.kept
                       .joins(meter_readings: :meter)
                       .where(meters: { property_id: property.id })
                       .where("meter_reading_events.recorded_at < ?", start_date.beginning_of_day)
                       .distinct
                       .order(recorded_at: :desc)
                       .first

    events = in_range.chronological.to_a
    events.unshift(boundary_event) if boundary_event && events.none? { |e| e.id == boundary_event.id }
    events
  end

  def compute_deltas(events)
    meters = property.meters.kept.main

    events.each_cons(2).map do |start_event, end_event|
      total = BigDecimal("0")

      meters.each do |meter|
        start_reading = start_event.meter_readings.find_by(meter: meter)
        end_reading = end_event.meter_readings.find_by(meter: meter)
        next unless start_reading && end_reading

        total += end_reading.value_kwh - start_reading.value_kwh
      end

      {
        end_date: end_event.recorded_at.to_date,
        total_kwh: total.to_f.round(2)
      }
    end
  end

  def aggregate_by_month(deltas)
    grouped = deltas.group_by { |d| d[:end_date].beginning_of_month }

    grouped.sort_by(&:first).map do |month, month_deltas|
      {
        month: month,
        total_kwh: month_deltas.sum { |d| d[:total_kwh] }.round(2),
        readings_count: month_deltas.size
      }
    end
  end

  def empty_result
    {
      months: [],
      total_kwh: 0.0,
      date_range: { start_date: start_date, end_date: end_date }
    }
  end
end
