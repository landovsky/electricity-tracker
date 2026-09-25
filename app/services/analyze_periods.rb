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
#     total_kwh: Decimal,           # primary delta (total consumption)
#     primary_delta: Decimal,       # delta across main meters
#     secondary_delta: Decimal,     # delta across secondary meters
#     present_visitors: [Visitor, ...],
#     manual_entries: [ManualConsumptionEntry, ...]
#   }
#
# Business Logic (from spec section 7):
#
# Step 1: Build the Timeline (see MeterTimeline)
# - Collect all MeterReadingEvents for the property, sorted by recorded_at
# - Each consecutive pair of boundary events defines a Period; meter deltas
#   carry each meter's last known reading forward across events that skipped it
# - Return periods whose end event falls in the range (plus the leading period
#   from the last event before the range); empty array if < 2 events
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
    range_start = date_range[:start_date].beginning_of_day
    range_end = date_range[:end_date].end_of_day

    # The timeline is NOT cut off at range_end: the period that straddles the
    # range end must exist while manual entries are assigned, otherwise an
    # entry dated on the last reading day inside the range would be claimed by
    # the earlier period here, yet by the straddling period in the next range's
    # report — and be counted in both. Periods starting after range_end can
    # never contain an entry that matters for this range, so they are skipped.
    segments = MeterTimeline.new(property: property).segments
                            .select { |segment| segment.start_event.recorded_at <= range_end }
    return [] if segments.empty?

    periods = build_periods(segments)
    assign_manual_entries(periods)

    # Periods are attributed by their end event. The first returned period
    # starts at the last event before the range (the boundary event), which
    # captures e.g. empty-house consumption across the range start.
    periods.select { |period| period[:end_time] >= range_start && period[:end_time] <= range_end }
  end

  private

  def build_periods(segments)
    main_ids = property.meters.kept.main.pluck(:id)
    secondary_ids = property.meters.kept.secondary.pluck(:id)

    segments.map do |segment|
      primary = segment.delta_for(main_ids)
      start_time = segment.start_event.recorded_at
      end_time = segment.end_event.recorded_at

      {
        start_event: segment.start_event,
        end_event: segment.end_event,
        start_time: start_time,
        end_time: end_time,
        duration_hours: calculate_duration_hours(start_time, end_time),
        total_kwh: primary,
        primary_delta: primary,
        secondary_delta: segment.delta_for(secondary_ids),
        present_visitors: find_present_visitors(start_time, end_time),
        manual_entries: []
      }
    end
  end

  def calculate_duration_hours(start_time, end_time)
    ((end_time - start_time) / 1.hour).round(2)
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

  # Assign every manual entry to exactly one period.
  #
  # An entry's date can touch two periods: a check-out day is both the last
  # day of the stay period and the first day of the following (often
  # empty-house) period. Among the periods whose date span contains the entry
  # date (inclusive at both ends), prefer one in which the entry's visitor was
  # present (E5: deducted from the shared pool of their own stay); otherwise
  # take the latest such period. Entries dated after the last reading stay
  # unassigned until a later reading closes a period around them.
  def assign_manual_entries(periods)
    entries = ManualConsumptionEntry.kept
                                    .where(property_id: property.id)
                                    .includes(:visitor)
                                    .order(:date, :id)

    entries.each do |entry|
      candidates = periods.select do |period|
        period[:start_time].to_date <= entry.date && entry.date <= period[:end_time].to_date
      end
      next if candidates.empty?

      own_stay = candidates.select { |period| period[:present_visitors].include?(entry.visitor) }
      target = (own_stay.presence || candidates).last
      target[:manual_entries] << entry
    end
  end
end
