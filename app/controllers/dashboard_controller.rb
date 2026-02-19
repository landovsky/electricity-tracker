class DashboardController < ApplicationController
  def index
    # Single property for now (future: multi-property support)
    @property = Property.kept.first

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

    # Recent activity - last 5 meter reading events
    @recent_events = MeterReadingEvent.kept
                                      .includes(:meter_readings, :stay_as_check_in, :stay_as_check_out)
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
