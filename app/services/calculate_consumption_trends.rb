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
    deltas = compute_deltas
    return empty_result if deltas.empty?

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

  # One delta per pair of consecutive readings, attributed to the month of the
  # later reading. MeterTimeline carries each meter's last known value forward,
  # so a reading that left one meter out (e.g. NT blank) doesn't lose that
  # meter's consumption, and an "initial" event for a newly added meter only
  # sets its baseline instead of splitting the period.
  def compute_deltas
    main_ids = property.meters.kept.main.pluck(:id)
    range_start = start_date.beginning_of_day

    MeterTimeline.new(property: property, until_time: end_date.end_of_day).segments
                 .select { |segment| segment.end_event.recorded_at >= range_start }
                 .map do |segment|
      {
        end_date: segment.end_event.recorded_at.to_date,
        total_kwh: segment.delta_for(main_ids).to_f.round(2)
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
