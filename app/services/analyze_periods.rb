# frozen_string_literal: true

# Service to analyze electricity consumption periods for a property.
#
# Builds a timeline from MeterReadingEvents and determines which visitors were
# present during each period. This is the foundation for the allocation algorithm.
#
# Input:
#   - property: Property model instance
#   - date_range: Date range (or hash with :start_date and :end_date)
#
# Output:
#   Array of period hashes, each containing:
#   {
#     start_event: MeterReadingEvent,
#     end_event: MeterReadingEvent,
#     start_time: Time,
#     end_time: Time,
#     duration_hours: Float,
#     total_kwh: Decimal,
#     upper_floor_kwh: Decimal,
#     present_visitors: [Visitor, ...],
#     manual_entries: [ManualConsumptionEntry, ...]
#   }
#
# Business Logic (from spec section 7):
#
# Step 1: Build the Timeline
# - Collect all MeterReadingEvents for the property within date range, sorted by recorded_at
# - Each consecutive pair of events defines a Period
# - Return empty array if < 2 events
#
# Step 2: Analyze Each Period
# - Determine present visitors: A visitor is "present" if they have a stay where:
#   * check_in_event.recorded_at <= period.start_time
#   * AND (check_out_event.recorded_at >= period.end_time OR check_out_event is nil)
#   In other words: the stay spans the entire period.
#
class AnalyzePeriods < ApplicationService
  object :property, class: Property
  hash :date_range, strip: false do
    date :start_date
    date :end_date
  end

  def execute
    events = fetch_meter_reading_events
    return [] if events.size < 2

    build_periods(events)
  end

  private

  def fetch_meter_reading_events
    MeterReadingEvent.kept
                     .joins(meter_readings: :meter)
                     .where(meters: { property_id: property.id })
                     .where(recorded_at: date_range[:start_date].beginning_of_day..date_range[:end_date].end_of_day)
                     .distinct
                     .chronological
  end

  def build_periods(events)
    periods = []

    events.each_cons(2) do |start_event, end_event|
      periods << {
        start_event: start_event,
        end_event: end_event,
        start_time: start_event.recorded_at,
        end_time: end_event.recorded_at,
        duration_hours: calculate_duration_hours(start_event.recorded_at, end_event.recorded_at),
        total_kwh: calculate_meter_delta(start_event, end_event, "main"),
        upper_floor_kwh: calculate_meter_delta(start_event, end_event, "secondary"),
        present_visitors: find_present_visitors(start_event.recorded_at, end_event.recorded_at),
        manual_entries: find_manual_entries(start_event.recorded_at, end_event.recorded_at)
      }
    end

    periods
  end

  def calculate_duration_hours(start_time, end_time)
    ((end_time - start_time) / 1.hour).round(2)
  end

  def calculate_meter_delta(start_event, end_event, meter_type)
    start_reading = start_event.meter_readings.joins(:meter).find_by(meters: { meter_type: meter_type })
    end_reading = end_event.meter_readings.joins(:meter).find_by(meters: { meter_type: meter_type })

    return BigDecimal("0") unless start_reading && end_reading

    end_reading.value_kwh - start_reading.value_kwh
  end

  def find_present_visitors(period_start, period_end)
    # A visitor is present if they have a stay that spans the entire period:
    # - check_in_event.recorded_at <= period_start
    # - AND (check_out_event.recorded_at >= period_end OR check_out_event is nil)
    stays = Stay.kept
                .where(property_id: property.id)
                .joins(:check_in_event)
                .where("meter_reading_events.recorded_at <= ?", period_start)
                .where(
                  "check_out_event_id IS NULL OR EXISTS (
                    SELECT 1 FROM meter_reading_events AS checkout_events
                    WHERE checkout_events.id = stays.check_out_event_id
                    AND checkout_events.recorded_at >= ?
                  )", period_end
                )
                .includes(:visitor)

    stays.map(&:visitor).uniq
  end

  def find_manual_entries(period_start, period_end)
    # Manual entries are attributed to a period if their date falls within the period's date range
    # We use inclusive ranges on both ends.
    # Note: If meter readings happen at different times on the same calendar day,
    # manual entries for that day will be attributed to the earlier period.
    start_date = period_start.to_date
    end_date = period_end.to_date

    ManualConsumptionEntry.kept
                          .where(property_id: property.id)
                          .where(date: start_date..end_date)
                          .order(:date)
  end
end
