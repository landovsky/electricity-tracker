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
  before_action :require_property

  # POST /stays
  # Check-in action - creates a new stay with meter readings
  def create
    outcome = CheckInVisitor.run(check_in_params)

    respond_to do |format|
      if outcome.valid?
        format.html { redirect_to root_path, notice: t("stays.check_in_success", name: outcome.result.visitor.name) }
        format.turbo_stream do
          flash.now[:notice] = t("stays.check_in_success", name: outcome.result.visitor.name)
          @succeeded = true
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
    # Only stays of properties the user can reach; ids are sequential and guessable.
    stay = Stay.kept.where(property: available_properties).find(params[:id])
    @property = stay.property
    outcome = CheckOutVisitor.run(check_out_params(stay))

    respond_to do |format|
      if outcome.valid?
        format.html { redirect_to root_path, notice: t("stays.check_out_success", name: stay.visitor.name) }
        format.turbo_stream do
          flash.now[:notice] = t("stays.check_out_success", name: stay.visitor.name)
          @succeeded = true
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
    redirect_to root_path, alert: t("stays.not_found")
  end

  private

  # Strong parameters for check-in
  def check_in_params
    property = find_property
    result = {
      visitor: find_visitor(property),
      property: property,
      recorded_by_user: current_user,
      recorded_at: parse_recorded_at(params[:recorded_at]),
      note: params[:note]
    }

    if params[:meter_readings].present?
      result[:meter_readings] = params[:meter_readings].to_unsafe_h
    else
      result[:main_meter_reading] = params[:main_meter_reading]
      result[:secondary_meter_reading] = params[:secondary_meter_reading]
    end

    result
  end

  # Strong parameters for check-out
  def check_out_params(stay)
    result = {
      stay: stay,
      property: stay.property,
      recorded_by_user: current_user,
      recorded_at: parse_recorded_at(params[:recorded_at]),
      note: params[:note]
    }

    if params[:meter_readings].present?
      result[:meter_readings] = params[:meter_readings].to_unsafe_h
    else
      result[:main_meter_reading] = params[:main_meter_reading]
      result[:secondary_meter_reading] = params[:secondary_meter_reading]
    end

    result
  end

  # The visitor must belong to the property the stay is recorded on.
  def find_visitor(property)
    property&.visitors&.kept&.find_by(id: params[:visitor_id])
  end

  # An explicit property_id is honoured only for properties the user can access
  # (membership + subdomain filter); anything else resolves to nil and fails validation.
  def find_property
    return @property if defined?(@property)

    @property = if params[:property_id].present?
      available_properties.find_by(id: params[:property_id])
    else
      current_property
    end
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

  def build_last_meter_readings_hash(property)
    property.meters.kept.each_with_object({}) do |meter, hash|
      reading = meter.last_reading
      next unless reading

      hash[meter.id] = {
        label: meter.label,
        value: reading.value_kwh,
        date: reading.meter_reading_event.recorded_at,
        meter_type: meter.meter_type,
        meter_group: meter.meter_group
      }
    end
  end

  # Load dashboard data for Turbo Stream responses
  def load_dashboard_data
    property = find_property || current_property
    @property_name = property.name
    @current_visitors = property.current_visitors.includes(:stays)
    # Same list as the dashboard: active visitors without an open stay
    @visitors_for_checkin = property.visitors.kept.active
                                    .where.not(id: @current_visitors.pluck(:id))
                                    .order(:name)
    @visitors_for_checkout = @current_visitors
    @default_visitor_id = current_user&.default_visitor_id
    @last_meter_readings = build_last_meter_readings_hash(property)
    @meters = property.meters.kept.form_order
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
