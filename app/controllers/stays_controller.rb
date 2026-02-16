# frozen_string_literal: true

# Controller for check-in and check-out operations.
#
# Implements UC1 (Visitor Check-in) and UC2 (Visitor Check-out) from the specification.
#
# Actions:
# - create (POST /stays) - Check-in a visitor with meter readings
# - check_out (PATCH /stays/:id/check_out) - Check-out a visitor with meter readings
#
# Both actions delegate business logic to service objects:
# - CheckInVisitor service for check-in
# - CheckOutVisitor service for check-out
#
# On success: redirects to root with success flash
# On failure: re-renders form with errors (for now, redirects with error flash)
class StaysController < ApplicationController
  before_action :require_authentication

  # POST /stays
  # Check-in action - creates a new stay with meter readings
  def create
    outcome = CheckInVisitor.run(check_in_params)

    if outcome.valid?
      redirect_to root_path, notice: "#{outcome.result.visitor.name} checked in successfully."
    else
      # Future enhancement: re-render inline form with Turbo Stream
      # For now: redirect back with error flash
      redirect_to root_path, alert: format_errors(outcome.errors)
    end
  end

  # PATCH /stays/:id/check_out
  # Check-out action - closes an existing stay with meter readings
  def check_out
    stay = Stay.kept.find(params[:id])
    outcome = CheckOutVisitor.run(check_out_params(stay))

    if outcome.valid?
      redirect_to root_path, notice: "#{stay.visitor.name} checked out successfully."
    else
      # Future enhancement: re-render inline form with Turbo Stream
      # For now: redirect back with error flash
      redirect_to root_path, alert: format_errors(outcome.errors)
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Stay not found."
  end

  private

  # Strong parameters for check-in
  def check_in_params
    {
      visitor: find_visitor,
      property: find_property,
      recorded_by_user: current_user,
      recorded_at: parse_recorded_at(params[:recorded_at]),
      main_meter_reading: params[:main_meter_reading],
      secondary_meter_reading: params[:secondary_meter_reading],
      note: params[:note]
    }
  end

  # Strong parameters for check-out
  def check_out_params(stay)
    {
      stay: stay,
      property: stay.property,
      recorded_by_user: current_user,
      recorded_at: parse_recorded_at(params[:recorded_at]),
      main_meter_reading: params[:main_meter_reading],
      secondary_meter_reading: params[:secondary_meter_reading],
      note: params[:note]
    }
  end

  def find_visitor
    Visitor.kept.find(params[:visitor_id])
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def find_property
    # For now, default to Property.first as per requirements
    # In the future, this could come from params[:property_id]
    if params[:property_id].present?
      Property.kept.find(params[:property_id])
    else
      Property.kept.first
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def parse_recorded_at(timestamp)
    return Time.current if timestamp.blank?

    Time.zone.parse(timestamp) || Time.current
  rescue ArgumentError
    Time.current
  end

  def format_errors(errors)
    errors.full_messages.join(". ")
  end

  # Stub authentication method
  # TODO: Implement proper authentication with magic link flow
  def require_authentication
    # For now, create or find a default user for testing
    # In production, this should check session and redirect to login if not authenticated
    @current_user ||= User.kept.first || User.create!(
      email: "test@example.com",
      name: "Test User",
      role: :member
    )
  end

  def current_user
    @current_user
  end
end
