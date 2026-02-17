# frozen_string_literal: true

class Dashboard::CheckOutFormComponent < ApplicationComponent
  def initialize(current_visitors:, last_readings:, meters:)
    @current_visitors = current_visitors
    @last_readings = last_readings
    @meters = meters
  end

  attr_reader :current_visitors, :last_readings, :meters

  def main_meter
    meters.find { |m| m.meter_type == "main" }
  end

  def secondary_meter
    meters.find { |m| m.meter_type == "secondary" }
  end

  def last_main_reading
    last_readings["main"]
  end

  def last_secondary_reading
    last_readings["secondary"]
  end

  def last_reading_hint(reading)
    return "" unless reading

    "Last reading: #{helpers.number_with_delimiter(reading[:value], delimiter: ',')} kWh (#{reading[:date].strftime('%b %d')})"
  end

  def visitor_options
    current_visitors.map do |visitor|
      stay = visitor.stays.find { |s| s.open? }
      checkin_date = stay&.check_in_event&.recorded_at&.strftime("%b %d") || "unknown"
      ["#{visitor.name} (since #{checkin_date})", stay&.id]
    end
  end
end
