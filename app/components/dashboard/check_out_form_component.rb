# frozen_string_literal: true

class Dashboard::CheckOutFormComponent < ApplicationComponent
  def initialize(current_visitors:, last_readings:, meters:, selected_visitor_id: nil, prefilled_readings: {}, camera_detections: [])
    @current_visitors = current_visitors
    @last_readings = last_readings
    @meters = meters
    @selected_visitor_id = selected_visitor_id
    @prefilled_readings = prefilled_readings
    @camera_detections = camera_detections
  end

  attr_reader :current_visitors, :last_readings, :meters, :selected_visitor_id, :prefilled_readings, :camera_detections

  # Groups meters for form layout. Meters sharing a meter_group render on one row.
  def meter_rows
    rows = []
    grouped = {}

    meters.each do |meter|
      if meter.meter_group.present?
        grouped[meter.meter_group] ||= []
        grouped[meter.meter_group] << meter
      else
        rows << [ meter ]
      end
    end

    grouped.each_value { |group| rows.unshift(group) }
    rows
  end

  def last_reading_for(meter)
    last_readings[meter.id]
  end

  def last_reading_hint(reading)
    return "" unless reading

    I18n.t("dashboard.check_out_form.last_reading",
           value: helpers.number_with_delimiter(reading[:value]),
           date: I18n.l(reading[:date].to_date, format: :short))
  end

  def meter_required?(meter)
    meter.main?
  end

  def prefilled_value_for(meter)
    prefilled_readings[meter.id]
  end

  def visitor_options
    current_visitors.map do |visitor|
      stay = visitor.stays.find { |s| s.open? }
      checkin_date = stay&.check_in_event&.recorded_at ? I18n.l(stay.check_in_event.recorded_at.to_date, format: :short) : "?"
      [ "#{visitor.name} (#{I18n.t('dashboard.check_out_form.since', date: checkin_date)})", stay&.id ]
    end
  end

  def visitor_options_with_data
    current_visitors.map do |visitor|
      stay = visitor.stays.find { |s| s.open? }
      checkin_date = stay&.check_in_event&.recorded_at ? I18n.l(stay.check_in_event.recorded_at.to_date, format: :short) : "?"
      label = "#{visitor.name} (#{I18n.t('dashboard.check_out_form.since', date: checkin_date)})"
      [ label, stay&.id, { "data-stay-id": stay&.id } ]
    end
  end

  def selected_stay_id
    return visitor_options.first&.last unless selected_visitor_id

    visitor = current_visitors.find { |v| v.id == selected_visitor_id }
    stay = visitor&.stays&.find { |s| s.open? }
    stay&.id || visitor_options.first&.last
  end
end
