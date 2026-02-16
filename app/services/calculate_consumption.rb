# frozen_string_literal: true

# Service to calculate electricity consumption allocation for a property over a date range.
#
# Implements the allocation algorithm from specification section 7:
# - Analyzes periods between meter reading events
# - Allocates consumption equally among present visitors
# - Handles empty-house periods (distributed among all visitors with stays)
# - Attributes manual entries directly to visitors
#
# Returns a hash with:
# - visitors: array of per-visitor consumption breakdown
# - total_consumption_kwh: sum of all visitor totals
# - total_meter_delta_kwh: meter delta for sanity checking
# - date_range: start and end dates
class CalculateConsumption < ApplicationService
  # Inputs
  object :property, class: Property
  date :start_date
  date :end_date
  boolean :include_archived_visitors, default: false

  # Custom validations
  validate :validate_date_range

  def execute
    # Step 1: Get period analysis using AnalyzePeriods service
    outcome = AnalyzePeriods.run(
      property: property,
      date_range: { start_date: start_date, end_date: end_date }
    )

    return empty_result unless outcome.valid?

    periods = outcome.result
    return empty_result if periods.empty?

    # Filter periods by archived visitor preference
    periods = filter_periods_by_visitor_status(periods) unless include_archived_visitors

    # Step 2: Initialize tracking
    visitor_totals = Hash.new do |h, k|
      h[k] = {
        period_shares: 0.0,
        manual_entries: 0.0,
        empty_house_share: 0.0
      }
    end
    unattributed_pool = 0.0
    visitors_with_stays = Set.new

    # Step 3: Allocate each period
    periods.each do |period|
      shared_kwh = period[:total_kwh] - period[:manual_entries].sum(&:kwh)

      if period[:present_visitors].any?
        # Split equally among present visitors
        per_visitor_share = shared_kwh / period[:present_visitors].count
        period[:present_visitors].each do |visitor|
          visitor_totals[visitor][:period_shares] += per_visitor_share
          visitors_with_stays << visitor
        end
      else
        # Empty house - add to unattributed pool
        unattributed_pool += shared_kwh
      end

      # Add manual entries directly to each visitor
      period[:manual_entries].each do |entry|
        visitor_totals[entry.visitor][:manual_entries] += entry.kwh
        visitors_with_stays << entry.visitor
      end
    end

    # Step 4: Distribute empty-house consumption
    if visitors_with_stays.any? && unattributed_pool > 0
      empty_house_per_visitor = unattributed_pool / visitors_with_stays.count
      visitors_with_stays.each do |visitor|
        visitor_totals[visitor][:empty_house_share] += empty_house_per_visitor
      end
    end

    # Step 5: Calculate totals
    visitors_result = visitor_totals.map do |visitor, breakdown|
      total_kwh = breakdown[:period_shares] + breakdown[:manual_entries] + breakdown[:empty_house_share]
      {
        visitor: visitor,
        period_shares_kwh: breakdown[:period_shares].round(2),
        manual_entries_kwh: breakdown[:manual_entries].round(2),
        empty_house_share_kwh: breakdown[:empty_house_share].round(2),
        total_kwh: total_kwh.round(2)
      }
    end

    # Sort by visitor name for consistent output
    visitors_result.sort_by! { |v| v[:visitor].name }

    {
      visitors: visitors_result,
      total_consumption_kwh: visitors_result.sum { |v| v[:total_kwh] }.round(2),
      total_meter_delta_kwh: calculate_total_meter_delta(periods).round(2),
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

  # Filter periods to exclude archived visitors unless explicitly included
  def filter_periods_by_visitor_status(periods)
    periods.map do |period|
      # Filter present visitors to only active ones
      filtered_visitors = period[:present_visitors].select { |v| v.status == "active" }

      # Filter manual entries to only those from active visitors
      filtered_manual_entries = period[:manual_entries].select { |e| e.visitor.status == "active" }

      period.merge(
        present_visitors: filtered_visitors,
        manual_entries: filtered_manual_entries
      )
    end
  end

  def calculate_total_meter_delta(periods)
    return 0.0 if periods.empty?

    # Sum up all period deltas
    periods.sum { |p| p[:total_kwh] }
  end
end
