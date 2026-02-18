# frozen_string_literal: true

class Dashboard::CheckOutFormComponent < ApplicationComponent
  def initialize(current_visitors:, last_readings:, meters:, selected_visitor_id: nil)
    @current_visitors = current_visitors
    @last_readings = last_readings
    @meters = meters
    @selected_visitor_id = selected_visitor_id
  end

  attr_reader :current_visitors, :last_readings, :meters, :selected_visitor_id

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

    I18n.t("dashboard.check_out_form.last_reading",
           value: helpers.number_with_delimiter(reading[:value]),
           date: I18n.l(reading[:date].to_date, format: :short))
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

  # Returns the stay_id to pre-select in the checkout dropdown.
  #
  # If a selected_visitor_id is provided, we find that visitor's open stay
  # and return its id. If the visitor has no open stay (not currently checked in),
  # we fall back to the first visitor in the list (existing behaviour).
  def selected_stay_id
    return visitor_options.first&.last unless selected_visitor_id

    visitor = current_visitors.find { |v| v.id == selected_visitor_id }
    stay = visitor&.stays&.find { |s| s.open? }
    stay&.id || visitor_options.first&.last
  end
end
