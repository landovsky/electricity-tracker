# frozen_string_literal: true

# Service to calculate electricity consumption allocation for a property over a date range.
#
# Implements a two-pool allocation algorithm for properties with subordinate meters:
#
# The primary (main) meter measures total consumption including the secondary meter's
# circuit. The secondary meter measures a subset (e.g., a garage/flat).
#
# For each period:
#   1. Secondary pool = secondary_delta → split among secondary participants
#   2. Primary pool = primary_delta - secondary_delta → split among primary participants
#
# Cross-period reconciliation:
#   When secondary_delta > 0 but primary_delta = 0 (secondary user didn't read primary),
#   the secondary consumption is attributed immediately but tracked as "unreconciled".
#   When the primary catches up in a later period, the unreconciled amount is subtracted
#   from the primary pool to prevent double-counting.
#
# IMPORTANT — RECONCILIATION STATE IS IN-MEMORY:
#   The `unreconciled_secondary` variable tracks secondary consumption that hasn't yet
#   been "seen" by the primary meter. This state is NOT persisted in the database.
#   To ensure correctness, we MUST process ALL periods from the property's first event,
#   not just periods within the requested date range. The date range only filters which
#   periods' allocations are included in the output.
#
#   If this algorithm is ever changed to only process in-range periods (e.g., for
#   performance), reconciliation state MUST be persisted or pre-computed. Otherwise,
#   unreconciled secondary consumption that crosses the date range boundary (e.g.,
#   secondary checkout on Dec 30, primary catchup on Jan 2) will be double-counted
#   in the later period's report.
#
# Manual entries are subtracted from the primary pool before splitting.
# Empty-house periods are distributed equally among all visitors with stays.
class CalculateConsumption < ApplicationService
  # Inputs
  object :property, class: Property
  date :start_date
  date :end_date
  boolean :include_archived_visitors, default: false

  # Custom validations
  validate :validate_date_range

  def execute
    # Fetch ALL periods from the property's first event to ensure reconciliation
    # state is correctly accumulated. Only allocations from in-range periods are
    # included in the output.
    all_periods = fetch_all_periods
    return empty_result if all_periods.empty?

    # Filter periods by archived visitor preference
    all_periods = filter_periods_by_visitor_status(all_periods) unless include_archived_visitors

    # Step 2: Initialize tracking
    visitor_totals = Hash.new do |h, k|
      h[k] = {
        period_shares: BigDecimal("0"),
        manual_entries: BigDecimal("0"),
        empty_house_share: BigDecimal("0")
      }
    end
    unattributed_pool = BigDecimal("0")
    visitors_with_stays = Set.new
    unreconciled_secondary = BigDecimal("0")

    # Step 3: Process ALL periods chronologically to build reconciliation state.
    # Only accumulate allocations for periods that fall within the requested range.
    all_periods.each do |period|
      primary_delta = period[:primary_delta]
      secondary_delta = period[:secondary_delta]
      in_range = period_in_range?(period)
      manual_kwh = in_range ? period[:manual_entries].sum(&:kwh) : 0
      all_visitors = period[:present_visitors]

      if all_visitors.any?
        if primary_delta == 0 && secondary_delta > 0
          # --- Unreconciled secondary consumption ---
          # Primary wasn't read (or didn't change), but secondary advanced.
          # Attribute secondary delta to the visitor who recorded it (end event owner),
          # and track as unreconciled for future primary catchup.
          if in_range
            secondary_participants = visitors_for_meter_pool(period, :secondary)
            secondary_participants = all_visitors if secondary_participants.empty?

            per_visitor = secondary_delta / secondary_participants.count
            secondary_participants.each do |visitor|
              visitor_totals[visitor][:period_shares] += per_visitor
              visitors_with_stays << visitor
            end
          end
          unreconciled_secondary += secondary_delta

        elsif primary_delta > 0
          # --- Normal period: primary delta is total consumption ---
          # Subtract unreconciled secondary (already attributed in a previous period)
          # to prevent double-counting when primary catches up.
          total_pool = primary_delta
          total_pool -= unreconciled_secondary
          unreconciled_secondary = BigDecimal("0")
          total_pool -= manual_kwh

          if in_range
            per_visitor = total_pool / all_visitors.count
            all_visitors.each do |visitor|
              visitor_totals[visitor][:period_shares] += per_visitor
              visitors_with_stays << visitor
            end
          end
        end
      else
        # Empty house
        empty_kwh = primary_delta - secondary_delta
        if primary_delta > 0
          empty_kwh -= unreconciled_secondary
          unreconciled_secondary = BigDecimal("0")
          empty_kwh -= manual_kwh
        end
        unattributed_pool += empty_kwh if in_range
      end

      # Add manual entries directly to each visitor
      if in_range
        period[:manual_entries].each do |entry|
          visitor_totals[entry.visitor][:manual_entries] += entry.kwh
          visitors_with_stays << entry.visitor
        end
      end
    end

    # Step 4: Distribute empty-house consumption
    if visitors_with_stays.any? && unattributed_pool > 0
      per_visitor = unattributed_pool / visitors_with_stays.count
      visitors_with_stays.each do |visitor|
        visitor_totals[visitor][:empty_house_share] += per_visitor
      end
    end

    # Step 5: Calculate totals
    visitors_result = visitor_totals.map do |visitor, breakdown|
      total_kwh = breakdown[:period_shares] + breakdown[:manual_entries] + breakdown[:empty_house_share]
      {
        visitor: visitor,
        period_shares_kwh: breakdown[:period_shares].to_f.round(2),
        manual_entries_kwh: breakdown[:manual_entries].to_f.round(2),
        empty_house_share_kwh: breakdown[:empty_house_share].to_f.round(2),
        total_kwh: total_kwh.to_f.round(2)
      }
    end

    visitors_result.sort_by! { |v| v[:visitor].name }

    in_range_periods = all_periods.select { |p| period_in_range?(p) }

    {
      visitors: visitors_result,
      total_consumption_kwh: visitors_result.sum { |v| v[:total_kwh] }.round(2),
      total_meter_delta_kwh: calculate_total_meter_delta(in_range_periods).to_f.round(2),
      date_range: { start_date: start_date, end_date: end_date }
    }
  end

  private

  def validate_date_range
    return unless start_date.present? && end_date.present?

    if end_date < start_date
      errors.add(:end_date, "must be after or equal to start_date")
    end
  end

  def empty_result
    {
      visitors: [],
      total_consumption_kwh: 0.0,
      total_meter_delta_kwh: 0.0,
      date_range: { start_date: start_date, end_date: end_date }
    }
  end

  # Fetch all periods from the property's very first event to the end of the
  # requested range. This ensures reconciliation state accumulated before the
  # requested start_date is carried forward correctly.
  def fetch_all_periods
    earliest = MeterReadingEvent.kept
                 .joins(meter_readings: :meter)
                 .where(meters: { property_id: property.id })
                 .minimum(:recorded_at)&.to_date

    return [] unless earliest

    outcome = AnalyzePeriods.run(
      property: property,
      date_range: { start_date: earliest, end_date: end_date }
    )

    outcome.valid? ? outcome.result : []
  end

  # A period is "in range" if its end_time falls within the requested date range.
  # We use end_time because that's when consumption is recorded/attributed.
  def period_in_range?(period)
    period[:end_time] >= start_date.beginning_of_day &&
      period[:end_time] <= end_date.end_of_day
  end

  # Determine which present visitors "own" a meter pool for this period.
  #
  # The end event of a period is the one that "closes" the period and records
  # the new meter state. The visitor whose check-in or check-out IS the end event
  # is the one who recorded the reading — they participate in that meter's pool.
  #
  # If no present visitor owns the end event (e.g., a periodic reading), all
  # present visitors share the pool.
  def visitors_for_meter_pool(period, meter_type)
    end_event_id = period[:end_event].id
    meter_ids = property.meters.kept.where(meter_type: meter_type).pluck(:id)
    return [] if meter_ids.empty?

    # Check the end event has a reading for this meter type
    has_reading = MeterReading.where(
      meter_reading_event_id: end_event_id,
      meter_id: meter_ids
    ).exists?
    return [] unless has_reading

    # Find the visitor whose check-in or check-out IS the end event
    owners = period[:present_visitors].select do |visitor|
      stays = Stay.kept.where(visitor: visitor, property_id: property.id)
      stays.any? do |stay|
        stay.check_in_event_id == end_event_id || stay.check_out_event_id == end_event_id
      end
    end

    owners
  end

  def filter_periods_by_visitor_status(periods)
    periods.map do |period|
      filtered_visitors = period[:present_visitors].select { |v| v.status == "active" }
      filtered_manual_entries = period[:manual_entries].select { |e| e.visitor.status == "active" }

      period.merge(
        present_visitors: filtered_visitors,
        manual_entries: filtered_manual_entries
      )
    end
  end

  def calculate_total_meter_delta(periods)
    return BigDecimal("0") if periods.empty?

    periods.sum { |p| p[:primary_delta] }
  end
end
