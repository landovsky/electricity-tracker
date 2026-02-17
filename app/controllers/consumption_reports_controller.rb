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
  end

  private

  def set_property
    @property = Property.kept.first

    unless @property
      redirect_to root_path, alert: t("no_property")
    end
  end

  def set_date_range
    if params[:year].present?
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
end
