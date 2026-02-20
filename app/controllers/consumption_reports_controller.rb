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
  # Generates consumption report for the specified date range or year
  def index
    outcome = CalculateConsumption.run(
      property: @property,
      start_date: @start_date,
      end_date: @end_date,
      include_archived_visitors: include_archived?
    )

    if outcome.valid?
      @report = outcome.result
    else
      flash.now[:alert] = format_errors(outcome.errors)
      @report = empty_report
    end

    @past_years = past_years_with_data

    respond_to do |format|
      format.html
      format.json { render json: build_debug_json } if Rails.env.development?
    end
  end

  private

  def set_property
    @property = Property.kept.first

    unless @property
      if request.format.json? && Rails.env.development?
        render json: { error: "No property found" }, status: :not_found
      else
        redirect_to root_path, alert: t("no_property")
      end
    end
  end

  def set_date_range
    if params[:year] == "all"
      # All time: from earliest event to today
      earliest = MeterReadingEvent.kept.minimum(:recorded_at)&.to_date
      @start_date = earliest || Date.new(Date.today.year, 1, 1)
      @end_date = Date.today
    elsif params[:year].present?
      # Year param: use Jan 1 to Dec 31 of that year
      year = params[:year].to_i
      @start_date = Date.new(year, 1, 1)
      @end_date = Date.new(year, 12, 31)
    elsif params[:start_date].present? && params[:end_date].present?
      # Explicit date range
      @start_date = Date.parse(params[:start_date])
      @end_date = Date.parse(params[:end_date])
    else
      # Default: current year
      current_year = Date.today.year
      @start_date = Date.new(current_year, 1, 1)
      @end_date = Date.new(current_year, 12, 31)
    end
  rescue ArgumentError => e
    # Invalid date format
    flash[:alert] = t("invalid_date", error: e.message)
    redirect_to root_path
  end

  # Up to 3 past years (before current) that have meter reading events
  def past_years_with_data
    current_year = Date.today.year
    MeterReadingEvent.kept
      .joins(meter_readings: :meter)
      .where(meters: { property_id: @property.id })
      .where("meter_reading_events.recorded_at < ?", Date.new(current_year, 1, 1))
      .select("DISTINCT strftime('%Y', recorded_at) AS yr")
      .map { |e| e.yr.to_i }
      .sort
      .last(3)
      .reverse
  end

  def include_archived?
    params[:include_archived] == "true"
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
          readings: e.meter_readings.includes(:meter).map { |r| { meter: r.meter.label, value_kwh: r.value_kwh.to_f } }
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
end
