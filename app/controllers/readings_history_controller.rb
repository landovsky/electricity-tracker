# frozen_string_literal: true

# Controller for readings history (Screen S3).
#
# Displays chronological log of all meter reading events and manual consumption entries.
#
# Actions:
# - index (GET /readings_history) - List all readings with optional filters
#
# Filterable by:
# - visitor_id: show only readings for a specific visitor
# - start_date: show readings from this date onward
# - end_date: show readings up to this date
class ReadingsHistoryController < ApplicationController
  before_action :set_property
  helper_method :year_filter_options, :selected_year

  # GET /readings_history
  # Lists all meter reading events and manual consumption entries
  def index
    @meter_reading_events = fetch_meter_reading_events
    @manual_consumption_entries = fetch_manual_consumption_entries
    @visitors = @property.visitors.kept.order(name: :asc)  # For filter dropdown
  end

  private

  def set_property
    @property = current_property

    unless @property
      redirect_to root_path, alert: t("no_property")
    end
  end

  def year_filter_options
    current_year = Date.current.year
    years = (current_year.downto(current_year - 5)).map { |y| [ y.to_s, y.to_s ] }
    years + [ [ t("history.all_time"), "" ] ]
  end

  # The year the filter shows and the list uses. Without any filter params the
  # current year is used (the dropdown shows it, so the list must match); an
  # explicit blank year is the "all time" option.
  def selected_year
    return params[:year].to_s if params.key?(:year)
    return "" if params[:start_date].present? || params[:end_date].present?

    Date.current.year.to_s
  end

  def date_range_from_params
    if selected_year.present?
      year = selected_year.to_i
      [ Date.new(year, 1, 1), Date.new(year, 12, 31) ]
    else
      start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : nil
      end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : nil
      [ start_date, end_date ]
    end
  end

  def fetch_meter_reading_events
    # Scope to current property via meters
    events = MeterReadingEvent.kept
                               .joins(meter_readings: :meter)
                               .where(meters: { property_id: @property.id })
                               .includes({ stay_as_check_in: :visitor }, { stay_as_check_out: :visitor },
                                         { meter_readings: :meter }, :recorded_by_user)
                               .distinct
                               .order(recorded_at: :desc)

    # Filter by visitor if specified (through stays)
    if params[:visitor_id].present?
      events = events.joins("LEFT JOIN stays AS check_in_stays ON meter_reading_events.id = check_in_stays.check_in_event_id")
                     .joins("LEFT JOIN stays AS check_out_stays ON meter_reading_events.id = check_out_stays.check_out_event_id")
                     .where("check_in_stays.visitor_id = ? OR check_out_stays.visitor_id = ?",
                            params[:visitor_id], params[:visitor_id])
    end

    # Filter by date range. recorded_at is stored in UTC; compare against local
    # (app time zone) day bounds so an event just after local midnight lands in
    # the same year/day it is displayed under.
    start_date, end_date = date_range_from_params
    events = events.where(meter_reading_events: { recorded_at: start_date.in_time_zone.beginning_of_day.. }) if start_date
    events = events.where(meter_reading_events: { recorded_at: ..end_date.in_time_zone.end_of_day }) if end_date

    events
  rescue ArgumentError => e
    flash.now[:alert] = t("invalid_date", error: e.message)
    MeterReadingEvent.none
  end

  def fetch_manual_consumption_entries
    entries = ManualConsumptionEntry.kept
                                    .where(property_id: @property.id)
                                    .includes(:visitor, :recorded_by_user)
                                    .order(date: :desc)

    entries = entries.where(visitor_id: params[:visitor_id]) if params[:visitor_id].present?

    # Filter by date range
    start_date, end_date = date_range_from_params
    entries = entries.where("date >= ?", start_date) if start_date
    entries = entries.where("date <= ?", end_date) if end_date

    entries
  rescue ArgumentError => e
    flash.now[:alert] = t("invalid_date", error: e.message)
    ManualConsumptionEntry.none
  end
end
