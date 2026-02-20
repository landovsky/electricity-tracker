# frozen_string_literal: true

# Controller for recording periodic meter readings on meter_only properties.
#
# Actions:
# - create (POST /odecty-mericu) - Record meter readings without a visitor/stay
class PeriodicReadingsController < ApplicationController
  # POST /odecty-mericu
  def create
    outcome = RecordMeterReading.run(
      property: current_property,
      recorded_by_user: current_user,
      recorded_at: parse_recorded_at(params[:recorded_at]),
      meter_readings: params[:meter_readings].to_unsafe_h,
      note: params[:note]
    )

    respond_to do |format|
      if outcome.valid?
        format.html { redirect_to root_path, notice: t("periodic_readings.success") }
        format.turbo_stream do
          flash.now[:notice] = t("periodic_readings.success")
          load_dashboard_data
        end
      else
        format.html { redirect_to root_path, alert: outcome.errors.full_messages.join(". ") }
        format.turbo_stream do
          flash.now[:alert] = outcome.errors.full_messages.join(". ")
          load_dashboard_data
        end
      end
    end
  end

  private

  def parse_recorded_at(timestamp)
    return Time.current if timestamp.blank?

    Time.zone.parse(timestamp) || Time.current
  rescue ArgumentError
    Time.current
  end

  def load_dashboard_data
    @property = current_property
    @property_name = @property.name
    @last_meter_readings = @property.meters.kept.each_with_object({}) do |meter, hash|
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
    @meters = @property.meters.kept.order(:meter_type, :meter_group, :label)
    @recent_events = MeterReadingEvent.kept
                                      .joins(meter_readings: :meter)
                                      .where(meters: { property_id: @property.id })
                                      .includes(:meter_readings, :stay_as_check_in, :stay_as_check_out)
                                      .distinct
                                      .recent
                                      .limit(5)
  end
end
