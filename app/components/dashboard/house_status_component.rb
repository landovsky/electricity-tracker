# frozen_string_literal: true

class Dashboard::HouseStatusComponent < ApplicationComponent
  def initialize(current_visitors:, last_meter_readings:)
    @current_visitors = current_visitors
    @last_meter_readings = last_meter_readings
  end

  attr_reader :current_visitors, :last_meter_readings

  def main_reading
    last_meter_readings["main"]
  end

  def secondary_reading
    last_meter_readings["secondary"]
  end
end
