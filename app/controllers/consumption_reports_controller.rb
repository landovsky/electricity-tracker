# frozen_string_literal: true

# Controller for consumption reports (Screen S2).
#
# Implements UC4 (Generate Consumption Report) from the specification.
#
# Actions:
# - index (GET /consumption_reports) - Generate report for a date range or year
#
# Delegates business logic to CalculateConsumption service.
# Accepts either 'year' param OR 'start_date'/'end_date' params.
class ConsumptionReportsController < ApplicationController
  skip_before_action :require_authentication, if: -> { request.format.json? && Rails.env.development? }
  skip_before_action :require_onboarding, if: -> { request.format.json? && Rails.env.development? }
  before_action :set_property
  before_action :set_date_range

  # GET /consumption_reports
  # Generates consumption report for the specified date range or year.
  # For meter_only properties, renders monthly trends instead of visitor allocation.
  def index
    @past_years = past_years_with_data

    if @property.meter_only?
      render_trends
    else
      render_allocation
    end
  end

  private

  def render_trends
    outcome = CalculateConsumptionTrends.run(
      property: @property,
      start_date: @start_date,
      end_date: @end_date
    )

    if outcome.valid?
      @trends = outcome.result
    else
      flash.now[:alert] = format_errors(outcome.errors)
      @trends = empty_trends
    end

    respond_to do |format|
      format.html { render :trends }
      format.json { render json: build_trends_debug_json } if Rails.env.development?
    end
  end

  def render_allocation
    outcome = CalculateConsumption.run(
      property: @property,
      start_date: @start_date,
      end_date: @end_date
    )

    if outcome.valid?
      @report = outcome.result
    else
      flash.now[:alert] = format_errors(outcome.errors)
      @report = empty_report
    end

    respond_to do |format|
      format.html
      format.json { render json: build_debug_json } if Rails.env.development?
    end
  end

  def set_property
    @property = current_property

    unless @property
      if request.format.json? && Rails.env.development?
        render json: { error: "No property found" }, status: :not_found
      else
        redirect_to root_path, alert: t("no_property")
      end
    end
  end

  def set_date_range
    year_param = date_param(:year)
    start_param = date_param(:start_date)
    end_param = date_param(:end_date)

    if year_param == "all"
      # All time: from earliest event to today (in the app time zone)
      earliest = MeterReadingEvent.kept
                  .joins(meter_readings: :meter)
                  .where(meters: { property_id: @property.id })
                  .minimum(:recorded_at)&.to_date
      @start_date = earliest || Date.new(Date.current.year, 1, 1)
      @end_date = Date.current
    elsif year_param.present?
      # Year param: use Jan 1 to Dec 31 of that year
      raise ArgumentError, year_param unless year_param.match?(/\A\d{4}\z/)

      year = year_param.to_i
      @start_date = Date.new(year, 1, 1)
      @end_date = Date.new(year, 12, 31)
    elsif start_param.present? && end_param.present?
      # Explicit date range
      @start_date = Date.parse(start_param)
      @end_date = Date.parse(end_param)
    else
      # Default: current year
      current_year = Date.current.year
      @start_date = Date.new(current_year, 1, 1)
      @end_date = Date.new(current_year, 12, 31)
    end
  rescue ArgumentError => e
    # Invalid date format
    flash[:alert] = t("invalid_date", error: e.message)
    redirect_to root_path
  end

  # Array/hash params (?year[]=2025) must end in the invalid-date redirect,
  # not a 500 from calling String methods on them.
  def date_param(key)
    value = params[key]
    return value.to_s if value.nil? || value.is_a?(String)

    raise ArgumentError, "#{key}: #{value.inspect}"
  end

  # Up to 3 past years (before current) that have meter reading events
  def past_years_with_data
    # Years are taken in the app time zone (recorded_at is stored in UTC), so a
    # reading at 00:30 on Jan 1 Prague time counts for the new year.
    MeterReadingEvent.kept
      .joins(meter_readings: :meter)
      .where(meters: { property_id: @property.id })
      .where("meter_reading_events.recorded_at < ?", Time.current.beginning_of_year)
      .distinct
      .pluck(:recorded_at)
      .map(&:year)
      .uniq
      .sort
      .last(3)
      .reverse
  end

  def empty_trends
    {
      months: [],
      total_kwh: 0.0,
      date_range: { start_date: @start_date, end_date: @end_date }
    }
  end

  def empty_report
    {
      visitors: [],
      total_consumption_kwh: 0.0,
      total_meter_delta_kwh: 0.0,
      date_range: { start_date: @start_date, end_date: @end_date }
    }
  end

  def format_errors(errors)
    errors.full_messages.join(". ")
  end

  def build_debug_json
    periods_outcome = AnalyzePeriods.run(
      property: @property,
      date_range: { start_date: @start_date, end_date: @end_date }
    )
    periods = periods_outcome.valid? ? periods_outcome.result : []

    {
      date_range: { start_date: @start_date, end_date: @end_date },
      report: {
        total_consumption_kwh: @report[:total_consumption_kwh],
        total_meter_delta_kwh: @report[:total_meter_delta_kwh],
        visitors: @report[:visitors].map do |v|
          {
            name: v[:visitor].name,
            id: v[:visitor].id,
            status: v[:visitor].status,
            period_shares_kwh: v[:period_shares_kwh],
            manual_entries_kwh: v[:manual_entries_kwh],
            empty_house_share_kwh: v[:empty_house_share_kwh],
            total_kwh: v[:total_kwh]
          }
        end
      },
      periods: periods.map.with_index do |p, i|
        {
          index: i,
          start_event_id: p[:start_event].id,
          end_event_id: p[:end_event].id,
          start_time: p[:start_time].iso8601,
          end_time: p[:end_time].iso8601,
          duration_hours: p[:duration_hours],
          total_kwh: p[:total_kwh].to_f,
          present_visitors: p[:present_visitors].map { |v| { id: v.id, name: v.name } },
          manual_entries: p[:manual_entries].map { |e| { id: e.id, visitor: e.visitor.name, kwh: e.kwh.to_f, date: e.date } }
        }
      end,
      meter_reading_events: @property.meters.kept.flat_map(&:meter_readings)
        .map(&:meter_reading_event).uniq.sort_by(&:recorded_at).map do |e|
        {
          id: e.id,
          recorded_at: e.recorded_at.iso8601,
          event_type: e.event_type,
          readings: e.meter_readings.includes(:meter).map { |r| { meter: r.meter.label, identifier: r.meter.identifier, value_kwh: r.value_kwh.to_f } }
        }
      end,
      stays: Stay.kept.where(property_id: @property.id).includes(:visitor, :check_in_event, :check_out_event)
        .order("meter_reading_events.recorded_at").map do |s|
        {
          id: s.id,
          visitor: s.visitor.name,
          visitor_id: s.visitor.id,
          status: s.status,
          check_in_at: s.check_in_event.recorded_at.iso8601,
          check_out_at: s.check_out_event&.recorded_at&.iso8601
        }
      end,
      manual_consumption_entries: ManualConsumptionEntry.kept.where(property_id: @property.id)
        .includes(:visitor).order(:date).map do |e|
        {
          id: e.id,
          visitor: e.visitor.name,
          date: e.date,
          kwh: e.kwh.to_f,
          note: e.note
        }
      end
    }
  end

  def build_trends_debug_json
    {
      date_range: { start_date: @start_date, end_date: @end_date },
      tracking_mode: "meter_only",
      trends: {
        total_kwh: @trends[:total_kwh],
        months: @trends[:months].map do |m|
          {
            month: m[:month].iso8601,
            total_kwh: m[:total_kwh],
            readings_count: m[:readings_count]
          }
        end
      },
      meter_reading_events: @property.meters.kept.flat_map(&:meter_readings)
        .map(&:meter_reading_event).uniq.sort_by(&:recorded_at).map do |e|
        {
          id: e.id,
          recorded_at: e.recorded_at.iso8601,
          event_type: e.event_type,
          readings: e.meter_readings.includes(:meter).map { |r| { meter: r.meter.label, identifier: r.meter.identifier, value_kwh: r.value_kwh.to_f } }
        }
      end
    }
  end
end
