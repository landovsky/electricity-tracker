# frozen_string_literal: true

class Dashboard::RecentActivityComponent < ApplicationComponent
  def initialize(recent_events:, recent_manual_entries:)
    @recent_events = recent_events
    @recent_manual_entries = recent_manual_entries
  end

  attr_reader :recent_events, :recent_manual_entries

  def combined_activity
    events = recent_events.map do |event|
      stay = event.stay_as_check_in || event.stay_as_check_out
      {
        type: event.event_type,
        visitor_name: stay&.visitor&.name || I18n.t("dashboard.recent_activity.unknown"),
        action: event.event_type == "check_in" ? I18n.t("dashboard.recent_activity.checked_in") : I18n.t("dashboard.recent_activity.checked_out"),
        date: event.recorded_at,
        details: meter_readings_summary(event)
      }
    end

    entries = recent_manual_entries.map do |entry|
      {
        type: "manual_entry",
        visitor_name: entry.visitor.name,
        action: I18n.t("dashboard.recent_activity.logged_kwh", kwh: entry.kwh),
        date: entry.date,
        details: entry.note
      }
    end

    (events + entries).sort_by { |item| item[:date] }.reverse
  end

  private

  def meter_readings_summary(event)
    readings = event.meter_readings
    return nil if readings.empty?

    parts = []
    main = readings.find { |r| r.meter.meter_type == "main" }
    secondary = readings.find { |r| r.meter.meter_type == "secondary" }

    parts << I18n.t("dashboard.recent_activity.main_reading", value: helpers.number_with_delimiter(main.value_kwh, delimiter: " ")) if main
    parts << "#{secondary.meter.label}: #{helpers.number_with_delimiter(secondary.value_kwh, delimiter: ',')}" if secondary

    parts.join(" &middot; ").html_safe
  end
end
