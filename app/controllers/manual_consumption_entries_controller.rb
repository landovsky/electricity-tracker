# frozen_string_literal: true

# Controller for creating manual consumption entries (UC3).
#
# Manual consumption entries allow visitors to record direct kWh consumption
# without a formal stay (e.g., EV charging).
#
# Routes:
# - POST /manual_consumption_entries - Create a new manual consumption entry
class ManualConsumptionEntriesController < ApplicationController
  # POST /manual_consumption_entries
  #
  # Creates a manual consumption entry via CreateManualConsumptionEntry service.
  #
  # Params:
  # - visitor_id (required)
  # - property_id (optional, defaults to Property.first)
  # - date (optional, defaults to Date.current)
  # - kwh (required)
  # - note (required)
  #
  # On success: redirects to root with success flash
  # On failure: redirects to root with error flash and params for form repopulation
  # On C8 warning: redirects to root with warning flash (soft validation)
  def create
    outcome = CreateManualConsumptionEntry.run(
      visitor: find_visitor,
      property: find_property,
      date: parse_date,
      kwh: params[:kwh],
      note: params[:note],
      recorded_by_user: current_user
    )

    respond_to do |format|
      if outcome.valid?
        # Entry was created successfully
        entry = outcome.result

        # Check for C8 soft validation warning
        if outcome.errors[:consumption_warning].any?
          format.html do
            flash[:warning] = outcome.errors[:consumption_warning].first
            redirect_to root_path
          end
          format.turbo_stream do
            flash.now[:warning] = outcome.errors[:consumption_warning].first
            load_dashboard_data
          end
        else
          format.html do
            flash[:success] = "Manual consumption entry recorded: #{entry.kwh} kWh for #{entry.visitor.name}"
            redirect_to root_path
          end
          format.turbo_stream do
            flash.now[:notice] = "Manual consumption entry recorded: #{entry.kwh} kWh for #{entry.visitor.name}"
            load_dashboard_data
          end
        end
      else
        # Validation failed - redirect with errors
        format.html do
          flash[:error] = format_errors(outcome.errors)
          redirect_to root_path
        end
        format.turbo_stream do
          flash.now[:alert] = format_errors(outcome.errors)
          load_dashboard_data
        end
      end
    end
  end

  private

  def find_visitor
    Visitor.find(params[:visitor_id])
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def find_property
    # Default to first property if not provided
    if params[:property_id].present?
      Property.find(params[:property_id])
    else
      Property.first
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def parse_date
    # Default to current date if not provided
    if params[:date].present?
      Date.parse(params[:date])
    else
      Date.current
    end
  rescue ArgumentError
    nil
  end

  def format_errors(errors)
    errors.full_messages.join(", ")
  end

  # Load dashboard data for Turbo Stream responses
  def load_dashboard_data
    property = find_property
    @current_visitors = property.current_visitors.includes(:stays)
    @visitors_for_checkin = Visitor.kept.order(:name)
    @visitors_for_checkout = @current_visitors
    @all_visitors = Visitor.kept.order(:name)
    @last_meter_readings = property.meters.map do |meter|
      reading = meter.meter_readings.kept.order(recorded_at: :desc).first
      next unless reading

      [meter.meter_type, {
        label: meter.label,
        value: reading.value,
        date: reading.recorded_at
      }]
    end.compact.to_h
    @meters = property.meters.kept.order(meter_type: :asc)
    @recent_events = property.events.kept.order(recorded_at: :desc).limit(10).includes(:visitor, :stay, :meter_reading)
  end
end
