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

  # GET /readings_history
  # Lists all meter reading events and manual consumption entries
  def index
    @meter_reading_events = fetch_meter_reading_events
    @manual_consumption_entries = fetch_manual_consumption_entries
    @visitors = Visitor.kept.order(name: :asc)  # For filter dropdown
  end

  private

  def set_property
    @property = Property.kept.first

    unless @property
      redirect_to root_path, alert: "No property found. Please create a property first."
    end
  end

  def fetch_meter_reading_events
    events = MeterReadingEvent.includes(:stay_as_check_in, :stay_as_check_out, :meter_readings, :recorded_by_user)
                               .order(recorded_at: :desc)

    # Filter by visitor if specified (through stays)
    if params[:visitor_id].present?
      events = events.joins("LEFT JOIN stays AS check_in_stays ON meter_reading_events.id = check_in_stays.check_in_event_id")
                     .joins("LEFT JOIN stays AS check_out_stays ON meter_reading_events.id = check_out_stays.check_out_event_id")
                     .where("check_in_stays.visitor_id = ? OR check_out_stays.visitor_id = ?",
                            params[:visitor_id], params[:visitor_id])
    end

    # Filter by date range if specified
    if params[:start_date].present?
      start_date = Date.parse(params[:start_date])
      events = events.where("DATE(recorded_at) >= ?", start_date)
    end

    if params[:end_date].present?
      end_date = Date.parse(params[:end_date])
      events = events.where("DATE(recorded_at) <= ?", end_date)
    end

    events
  rescue ArgumentError => e
    # Invalid date format
    flash.now[:alert] = "Invalid date format: #{e.message}"
    MeterReadingEvent.none
  end

  def fetch_manual_consumption_entries
    entries = ManualConsumptionEntry.includes(:visitor, :recorded_by_user)
                                    .order(date: :desc)

    # Filter by visitor if specified
    entries = entries.where(visitor_id: params[:visitor_id]) if params[:visitor_id].present?

    # Filter by date range if specified
    if params[:start_date].present?
      start_date = Date.parse(params[:start_date])
      entries = entries.where("date >= ?", start_date)
    end

    if params[:end_date].present?
      end_date = Date.parse(params[:end_date])
      entries = entries.where("date <= ?", end_date)
    end

    entries
  rescue ArgumentError => e
    # Invalid date format
    flash.now[:alert] = "Invalid date format: #{e.message}"
    ManualConsumptionEntry.none
  end

end
