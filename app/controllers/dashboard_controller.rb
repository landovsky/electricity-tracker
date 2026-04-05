class DashboardController < ApplicationController
  def index
    @property = current_property

    # Return early if no property exists (empty state)
    return unless @property

    # Common data for both modes
    @last_meter_readings = build_last_meter_readings
    @meters = @property.meters.kept.order(:meter_type, :meter_group, label: :desc)
    @recent_events = MeterReadingEvent.kept
                                      .joins(meter_readings: :meter)
                                      .where(meters: { property_id: @property.id })
                                      .includes(:meter_readings, :stay_as_check_in, :stay_as_check_out)
                                      .distinct
                                      .recent
                                      .limit(5)
    @prefilled_readings = build_prefilled_readings(params[:camera_session_id])
    @camera_detections = load_camera_detections(params[:camera_session_id])

    if @property.meter_only?
      @current_visitors = []
      @recent_manual_entries = []
    else
      load_visitors_data
    end
  end

  private

  def load_visitors_data
    @current_visitors = @property.visitors.kept
                               .joins(:stays)
                               .where(stays: { check_out_event_id: nil })
                               .includes(stays: [ :check_in_event ])
                               .distinct
                               .order(:name)

    @recent_manual_entries = ManualConsumptionEntry.kept
                                                   .where(property_id: @property.id)
                                                   .includes(:visitor)
                                                   .recent
                                                   .limit(5)

    @default_visitor_id = current_user&.default_visitor_id
    @default_tab = params[:event_type] == "check_out" ? "checkout" : "checkin"

    @visitors_for_checkin = @property.visitors.kept
                                   .active
                                   .where.not(id: @current_visitors.pluck(:id))
                                   .order(:name)

    @visitors_for_checkout = @current_visitors
  end

  def load_camera_detections(camera_session_id)
    return [] unless camera_session_id.present?

    MeterPhotoDetection
      .for_session(camera_session_id)
      .usable
      .where.not(meter_id: nil)
      .includes(:meter, photo_attachment: :blob)
      .order(:created_at)
  end

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
