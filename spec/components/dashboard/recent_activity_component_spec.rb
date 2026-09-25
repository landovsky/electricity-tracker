# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::RecentActivityComponent, type: :component do
  let(:visitor) { instance_double("Visitor", name: "Alice") }
  let(:meter) { instance_double("Meter", meter_type: "main", label: "Main meter", unit: "kWh") }
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
    expect(page).to have_link("View all")
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

    expect(page).to have_text("Main: 12,487 kWh")
  end

  context "an admin gave the secondary meter a label containing HTML" do
    let(:secondary_meter) do
      instance_double("Meter", meter_type: "secondary", label: "<img src=x onerror=alert(1)>", unit: "<b>kWh</b>")
    end
    let(:secondary_reading) { instance_double("MeterReading", meter: secondary_meter, value_kwh: 500) }
    let(:event) do
      instance_double("Event", event_type: "periodic", recorded_at: 1.day.ago, meter_readings: [ meter_reading, secondary_reading ])
    end

    it "shows the label as text instead of running it as markup on every member's dashboard" do
      render_inline(described_class.new(recent_events: [ event ], recent_manual_entries: []))

      expect(page).not_to have_css("img")
      expect(page).not_to have_css("b")
      expect(page).to have_text("<img src=x onerror=alert(1)>: 500 <b>kWh</b>")
      expect(page).to have_text("Main: 12,487 kWh · ")
    end
  end

  context "a manual entry was logged with a decimal amount in the Czech UI" do
    let(:manual_entry) do
      instance_double("ManualConsumptionEntry", visitor: visitor, kwh: BigDecimal("12.5"), date: 1.day.ago, note: nil)
    end

    it "formats kWh with a decimal comma, matching the history page" do
      I18n.with_locale(:cs) do
        render_inline(described_class.new(recent_events: [], recent_manual_entries: [ manual_entry ]))
      end

      expect(page).to have_text("12,5 kWh")
      expect(page).not_to have_text("12.5")
    end
  end
end
