# frozen_string_literal: true

class Dashboard::HouseStatusComponent < ApplicationComponent
  def initialize(current_visitors:, last_meter_readings:, property_name: nil)
    @current_visitors = current_visitors
    @last_meter_readings = last_meter_readings
    @property_name = property_name
  end

  attr_reader :current_visitors, :last_meter_readings, :property_name

  def main_reading
    last_meter_readings["main"]
  end

  def secondary_reading
    last_meter_readings["secondary"]
  end
end
