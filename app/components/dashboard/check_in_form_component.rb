# frozen_string_literal: true

class Dashboard::CheckInFormComponent < ApplicationComponent
  def initialize(visitors:, last_readings:, meters:, selected_visitor_id: nil)
    @visitors = visitors
    @last_readings = last_readings
    @meters = meters
    @selected_visitor_id = selected_visitor_id
  end

  attr_reader :visitors, :last_readings, :meters, :selected_visitor_id

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

    I18n.t("dashboard.check_in_form.last_reading",
           value: helpers.number_with_delimiter(reading[:value]),
           date: I18n.l(reading[:date].to_date, format: :short))
  end
end
