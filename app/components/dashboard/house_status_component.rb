# frozen_string_literal: true

class Dashboard::HouseStatusComponent < ApplicationComponent
  def initialize(current_visitors:, last_meter_readings:, property_name: nil, tracking_mode: "visitors")
    @current_visitors = current_visitors
    @last_meter_readings = last_meter_readings
    @property_name = property_name
    @tracking_mode = tracking_mode
  end

  attr_reader :current_visitors, :last_meter_readings, :property_name, :tracking_mode

  def meter_only?
    tracking_mode == "meter_only"
  end

  # Returns readings sorted: main meters first, then secondary
  def sorted_readings
    last_meter_readings.values.sort_by { |r| r[:meter_type] == "main" ? 0 : 1 }
  end

  def icon_for_reading(reading)
    reading[:meter_type] == "main" ? "fa-gauge-high" : "fa-gauge"
  end
end
