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

    respond_to do |format|
      if outcome.valid?
        format.html { redirect_to root_path, notice: "#{outcome.result.visitor.name} checked in successfully." }
        format.turbo_stream do
          flash.now[:notice] = "#{outcome.result.visitor.name} checked in successfully."
          load_dashboard_data
        end
      else
        format.html { redirect_to root_path, alert: format_errors(outcome.errors) }
        format.turbo_stream do
          flash.now[:alert] = format_errors(outcome.errors)
          load_dashboard_data
        end
      end
    end
  end

  # PATCH /stays/:id/check_out
  # Check-out action - closes an existing stay with meter readings
  def check_out
    stay = Stay.kept.find(params[:id])
    outcome = CheckOutVisitor.run(check_out_params(stay))

    respond_to do |format|
      if outcome.valid?
        format.html { redirect_to root_path, notice: "#{stay.visitor.name} checked out successfully." }
        format.turbo_stream do
          flash.now[:notice] = "#{stay.visitor.name} checked out successfully."
          load_dashboard_data
        end
      else
        format.html { redirect_to root_path, alert: format_errors(outcome.errors) }
        format.turbo_stream do
          flash.now[:alert] = format_errors(outcome.errors)
          load_dashboard_data
        end
      end
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

  # Load dashboard data for Turbo Stream responses
  def load_dashboard_data
    property = find_property
    @current_visitors = property.current_visitors.includes(:stays)
    @visitors_for_checkin = Visitor.kept.order(:name)
    @visitors_for_checkout = @current_visitors
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
