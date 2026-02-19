# frozen_string_literal: true

class Dashboard::CheckInFormComponent < ApplicationComponent
  def initialize(visitors:, last_readings:, meters:, selected_visitor_id: nil)
    @visitors = visitors
    @last_readings = last_readings
    @meters = meters
    @selected_visitor_id = selected_visitor_id
  end

  attr_reader :visitors, :last_readings, :meters, :selected_visitor_id

  # Groups meters for form layout. Meters sharing a meter_group render on one row.
  # Ungrouped meters get their own row.
  # Returns array of arrays: [[meter], [meter_vt, meter_nt], ...]
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

    I18n.t("dashboard.check_in_form.last_reading",
           value: helpers.number_with_delimiter(reading[:value]),
           date: I18n.l(reading[:date].to_date, format: :short))
  end

  def meter_required?(meter)
    meter.main?
  end
end
