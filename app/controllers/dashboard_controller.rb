class DashboardController < ApplicationController
  def index
    @property = current_property

    # Return early if no property exists (empty state)
    return unless @property

    # Current visitors (those with open stays)
    @current_visitors = Visitor.kept
                               .joins(:stays)
                               .where(stays: { check_out_event_id: nil })
                               .where(stays: { property_id: @property.id })
                               .includes(stays: [ :check_in_event ])
                               .distinct
                               .order(:name)

    # Last meter readings keyed by meter ID
    @last_meter_readings = build_last_meter_readings

    # Recent activity - last 5 meter reading events scoped to property meters
    @recent_events = MeterReadingEvent.kept
                                      .joins(meter_readings: :meter)
                                      .where(meters: { property_id: @property.id })
                                      .includes(:meter_readings, :stay_as_check_in, :stay_as_check_out)
                                      .distinct
                                      .recent
                                      .limit(5)

    # Recent manual entries - last 5 manual consumption entries
    @recent_manual_entries = ManualConsumptionEntry.kept
                                                   .where(property_id: @property.id)
                                                   .includes(:visitor)
                                                   .recent
                                                   .limit(5)

    # Default visitor for pre-selecting in forms
    @default_visitor_id = current_user&.default_visitor_id

    # Prefill meter readings from camera session
    @prefilled_readings = build_prefilled_readings(params[:camera_session_id])

    # Auto-select tab based on event_type from camera
    @default_tab = params[:event_type] == "check_out" ? "checkout" : "checkin"

    # Data for inline forms

    # Visitors available for check-in (active visitors without open stays)
    @visitors_for_checkin = Visitor.kept
                                   .active
                                   .where.not(id: @current_visitors.pluck(:id))
                                   .order(:name)

    # Visitors available for check-out (visitors with open stays)
    @visitors_for_checkout = @current_visitors

    # Meters for the property (for form fields)
    @meters = @property.meters.kept.order(:meter_type, :meter_group, :label)
  end

  private

  def build_prefilled_readings(camera_session_id)
    return {} unless camera_session_id.present?

    MeterPhotoDetection
      .for_session(camera_session_id)
      .usable
      .where.not(meter_id: nil)
      .order(:created_at)
      .each_with_object({}) do |detection, hash|
        hash[detection.meter_id] = detection.detected_value
      end
  end

  def build_last_meter_readings
    return {} unless @property

    @property.meters.kept.each_with_object({}) do |meter, hash|
      reading = meter.last_reading
      next unless reading

      hash[meter.id] = {
        value: reading.value_kwh,
        date: reading.meter_reading_event.recorded_at,
        label: meter.label,
        meter_type: meter.meter_type,
        meter_group: meter.meter_group
      }
    end
  end
end
