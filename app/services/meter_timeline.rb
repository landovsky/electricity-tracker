# frozen_string_literal: true

# Chronological walk over a property's meter reading events, producing
# consecutive period boundaries with per-meter kWh deltas.
#
# Shared by AnalyzePeriods (visitor allocation) and CalculateConsumptionTrends
# (meter_only monthly totals) so both measure consumption the same way.
#
# Two rules keep every kWh counted exactly once:
#
# 1. Per-meter carry-forward. A meter's delta is measured from its last known
#    reading (from whatever earlier event read it), not only from the period's
#    start event. An event that leaves a meter out (E8 secondary not read, a
#    periodic reading that skipped NT) therefore never drops that meter's
#    consumption — it is charged to the period in which the meter is next read.
#
# 2. Baseline-only initial events. An "initial" event created when a meter is
#    added mid-life (MetersController#create) carries only the new meter's
#    reading. If it lacks a reading for a main meter that was already being
#    read, it is not a period boundary — it only sets the new meter's baseline.
#    Otherwise it would split an ongoing period and leave half of it without a
#    main-meter reading. An initial event that covers every already-read main
#    meter (e.g. the property's very first reading) stays a boundary.
class MeterTimeline
  Segment = Data.define(:start_event, :end_event, :deltas) do
    # Sum of deltas for the given meters (Meter records or ids)
    def delta_for(meters)
      ids = meters.map { |m| m.is_a?(Meter) ? m.id : m }
      ids.sum(BigDecimal("0")) { |id| deltas.fetch(id, BigDecimal("0")) }
    end
  end

  # until_time: nil walks the whole timeline
  def initialize(property:, until_time: nil)
    @property = property
    @until_time = until_time
  end

  # Returns [Segment, ...] for every pair of consecutive boundary events
  # recorded up to until_time (or all of them), oldest first.
  def segments
    meter_ids = @property.meters.kept.pluck(:id).to_set
    main_ids = @property.meters.kept.main.pluck(:id).to_set

    last_values = {}
    known_main = Set.new
    previous_boundary = nil
    result = []

    events.each do |event|
      readings = event.meter_readings.select { |r| meter_ids.include?(r.meter_id) }
      event_main = readings.map(&:meter_id).select { |id| main_ids.include?(id) }.to_set

      boundary = !event.initial? || known_main.subset?(event_main)

      if boundary
        if previous_boundary
          deltas = readings.each_with_object({}) do |reading, acc|
            next unless last_values.key?(reading.meter_id)

            acc[reading.meter_id] = reading.value_kwh - last_values[reading.meter_id]
          end
          result << Segment.new(start_event: previous_boundary, end_event: event, deltas: deltas)
        end
        previous_boundary = event
      end

      readings.each { |r| last_values[r.meter_id] = r.value_kwh }
      known_main.merge(event_main)
    end

    result
  end

  private

  def events
    scope = MeterReadingEvent.kept
                             .where(id: MeterReading.joins(:meter)
                                                    .where(meters: { property_id: @property.id })
                                                    .select(:meter_reading_event_id))
    scope = scope.where("meter_reading_events.recorded_at <= ?", @until_time) if @until_time
    scope.includes(:meter_readings).order(:recorded_at, :id).to_a
  end
end
