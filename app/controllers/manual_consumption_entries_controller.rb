# frozen_string_literal: true

# Controller for creating manual consumption entries (UC3).
#
# Manual consumption entries allow visitors to record direct kWh consumption
# without a formal stay (e.g., EV charging).
#
# Routes:
# - POST /manual_consumption_entries - Create a new manual consumption entry
class ManualConsumptionEntriesController < ApplicationController
  before_action :require_authentication

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

    if outcome.valid?
      # Entry was created successfully
      entry = outcome.result

      # Check for C8 soft validation warning
      if outcome.errors[:consumption_warning].any?
        flash[:warning] = outcome.errors[:consumption_warning].first
      else
        flash[:success] = "Manual consumption entry recorded: #{entry.kwh} kWh for #{entry.visitor.name}"
      end

      redirect_to root_path
    else
      # Validation failed - redirect with errors
      flash[:error] = format_errors(outcome.errors)
      redirect_to root_path
    end
  end

  private

  # Stub for authentication
  # TODO: Implement real authentication when sessions controller is complete
  def require_authentication
    # For now, this is a no-op stub
    # When real authentication is implemented, this should:
    # - Check if user is logged in (session[:user_id] present)
    # - Redirect to login_path with flash[:error] if not authenticated
  end

  # Stub for current_user
  # TODO: Implement real current_user when sessions controller is complete
  def current_user
    # For now, return the first user or create one for testing
    # This is a temporary stub until authentication is implemented
    @current_user ||= User.first || User.create!(
      email: "system@example.com",
      name: "System User",
      role: "member"
    )
  end

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
end
