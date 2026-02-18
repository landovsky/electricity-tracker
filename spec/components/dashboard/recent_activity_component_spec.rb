# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::RecentActivityComponent, type: :component do
  let(:visitor) { instance_double("Visitor", name: "Alice") }
  let(:meter) { instance_double("Meter", meter_type: "main", label: "Main meter") }
  let(:meter_reading) { instance_double("MeterReading", meter: meter, value_kwh: 12_487) }
  let(:stay) { instance_double("Stay", visitor: visitor) }
  let(:event) do
    instance_double(
      "Event",
      event_type: "check_in",
      recorded_at: 2.days.ago,
      stay_as_check_in: stay,
      stay_as_check_out: nil,
      meter_readings: [ meter_reading ]
    )
  end
  let(:manual_entry) do
    instance_double(
      "ManualConsumptionEntry",
      visitor: visitor,
      kwh: 15,
      date: 1.day.ago,
      note: "EV charging"
    )
  end

  it "renders recent activity section with header" do
    render_inline(described_class.new(
      recent_events: [ event ],
      recent_manual_entries: []
    ))

    expect(page).to have_css("h2", text: "Recent activity")
    expect(page).to have_link("View all", href: "/readings_history")
  end

  it "renders events and manual entries combined and sorted" do
    render_inline(described_class.new(
      recent_events: [ event ],
      recent_manual_entries: [ manual_entry ]
    ))

    expect(page).to have_text("Alice")
    expect(page).to have_text("checked in")
    expect(page).to have_text("logged 15 kWh")
  end

  it "renders empty state when no activity" do
    render_inline(described_class.new(
      recent_events: [],
      recent_manual_entries: []
    ))

    expect(page).to have_text("No recent activity.")
  end

  it "renders meter readings summary for events" do
    render_inline(described_class.new(
      recent_events: [ event ],
      recent_manual_entries: []
    ))

    expect(page).to have_text("Main: 12,487")
  end
end
