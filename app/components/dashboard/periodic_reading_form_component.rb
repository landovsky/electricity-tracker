# frozen_string_literal: true

class Dashboard::PeriodicReadingFormComponent < ApplicationComponent
  def initialize(meters:, last_readings:, prefilled_readings: {}, camera_detections: [])
    @meters = meters
    @last_readings = last_readings
    @prefilled_readings = prefilled_readings
    @camera_detections = camera_detections
  end

  attr_reader :meters, :last_readings, :prefilled_readings, :camera_detections

  def meter_rows
    rows = []
    grouped = {}

    meters.each do |meter|
      if meter.meter_group.present?
        grouped[meter.meter_group] ||= []
        grouped[meter.meter_group] << meter
      else
        rows << [meter]
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

    I18n.t("dashboard.periodic_reading_form.last_reading",
           value: helpers.number_with_delimiter(reading[:value]),
           date: I18n.l(reading[:date].to_date, format: :short))
  end

  def prefilled_value_for(meter)
    prefilled_readings[meter.id]
  end
end
