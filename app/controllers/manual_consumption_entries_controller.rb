# frozen_string_literal: true

# Controller for creating manual consumption entries (UC3).
#
# Manual consumption entries allow visitors to record direct kWh consumption
# without a formal stay (e.g., EV charging).
#
# Routes:
# - POST /manual_consumption_entries - Create a new manual consumption entry
class ManualConsumptionEntriesController < ApplicationController
  before_action :require_property

  # POST /manual_consumption_entries
  #
  # Creates a manual consumption entry via CreateManualConsumptionEntry service.
  #
  # Params:
  # - visitor_id (required)
  # - property_id (optional, defaults to current_property; must be accessible to the user)
  # - date (optional, defaults to Date.current)
  # - kwh (required)
  # - note (required)
  #
  # On success: redirects to root with success flash
  # On failure: redirects to root with error flash and params for form repopulation
  # On C8 warning: redirects to root with warning flash (soft validation)
  def create
    property = find_property
    outcome = CreateManualConsumptionEntry.run(
      visitor: find_visitor(property),
      property: property,
      date: parse_date,
      kwh: params[:kwh],
      note: params[:note],
      recorded_by_user: current_user
    )

    respond_to do |format|
      if outcome.valid?
        # Entry was created successfully
        entry = outcome.result

        # C8 soft validation: the entry is saved, but the user is warned
        if outcome.consumption_warning
          format.html do
            flash[:warning] = outcome.consumption_warning
            redirect_to root_path
          end
          format.turbo_stream do
            flash.now[:warning] = outcome.consumption_warning
            load_dashboard_data
          end
        else
          format.html do
            flash[:success] = t("manual_entries.success", kwh: helpers.number_with_precision(entry.kwh, precision: 2, strip_insignificant_zeros: true), name: entry.visitor.name)
            redirect_to root_path
          end
          format.turbo_stream do
            flash.now[:notice] = t("manual_entries.success", kwh: helpers.number_with_precision(entry.kwh, precision: 2, strip_insignificant_zeros: true), name: entry.visitor.name)
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

  # The visitor must belong to the property the entry is recorded on.
  def find_visitor(property)
    property&.visitors&.kept&.find_by(id: params[:visitor_id])
  end

  # An explicit property_id is honoured only for (kept) properties the user can
  # access; anything else resolves to nil and fails validation.
  def find_property
    return @property if defined?(@property)

    @property = if params[:property_id].present?
      available_properties.find_by(id: params[:property_id])
    else
      current_property
    end
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

  # Load dashboard data for Turbo Stream responses.
  # Only what manual_consumption_entries/create.turbo_stream.erb renders.
  def load_dashboard_data
    property = find_property || current_property
    @all_visitors = property.visitors.kept.order(:name)
    @default_visitor_id = current_user&.default_visitor_id
    @recent_events = MeterReadingEvent.kept
                                      .joins(meter_readings: :meter)
                                      .where(meters: { property_id: property.id })
                                      .includes(:meter_readings, :stay_as_check_in, :stay_as_check_out)
                                      .distinct
                                      .recent
                                      .limit(10)
    @recent_manual_entries = ManualConsumptionEntry.kept
                                                    .where(property_id: property.id)
                                                    .includes(:visitor)
                                                    .recent
                                                    .limit(5)
  end
end
