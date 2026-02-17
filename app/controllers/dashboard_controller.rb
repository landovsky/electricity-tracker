class DashboardController < ApplicationController
  # Disable host authorization in test environment
  # This is needed because test.rb config changes aren't being picked up consistently
  skip_before_action :verify_authenticity_token if Rails.env.test?

  # TODO: Enable authentication once auth system is implemented
  # before_action :require_authentication

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

    # Last meter readings (most recent reading for each meter type)
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

    # Data for inline forms

    # Visitors available for check-in (active visitors without open stays)
    @visitors_for_checkin = Visitor.kept
                                   .active
                                   .where.not(id: @current_visitors.pluck(:id))
                                   .order(:name)

    # Visitors available for check-out (visitors with open stays)
    @visitors_for_checkout = @current_visitors

    # Meters for the property (for form fields)
    @meters = @property.meters.kept.order(:meter_type)
  end

  private

  def build_last_meter_readings
    return {} unless @property

    readings_hash = {}

    # Get the most recent meter reading event with readings
    last_event = MeterReadingEvent.kept
                                  .joins(:meter_readings)
                                  .includes(meter_readings: :meter)
                                  .recent
                                  .first

    return readings_hash unless last_event

    # Build hash of meter_type => { value, date, meter_label }
    last_event.meter_readings.each do |reading|
      readings_hash[reading.meter.meter_type] = {
        value: reading.value_kwh,
        date: last_event.recorded_at,
        label: reading.meter.label
      }
    end

    readings_hash
  end
end
