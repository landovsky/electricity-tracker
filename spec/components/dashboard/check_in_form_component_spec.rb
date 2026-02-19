# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::CheckInFormComponent, type: :component do
  let(:visitor) { instance_double("Visitor", id: 1, name: "Alice") }
  let(:main_meter) { instance_double("Meter", id: 1, meter_type: "main", label: "Main meter", main?: true, meter_group: nil) }
  let(:secondary_meter) { instance_double("Meter", id: 2, meter_type: "secondary", label: "Upper floor", main?: false, meter_group: nil) }
  let(:meters) { [ main_meter, secondary_meter ] }
  let(:last_readings) do
    {
      1 => { value: 12_487, date: Date.parse("2026-02-15"), meter_type: "main" },
      2 => { value: 3_219, date: Date.parse("2026-02-15"), meter_type: "secondary" }
    }
  end

  it "renders check-in form with visitor select" do
    render_inline(described_class.new(
      visitors: [ visitor ],
      last_readings: last_readings,
      meters: meters
    ))

    expect(page).to have_select("visitor_id")
    expect(page).to have_field("recorded_at")
    expect(page).to have_button("Check In")
  end

  it "renders meter reading fields with last reading hints" do
    render_inline(described_class.new(
      visitors: [ visitor ],
      last_readings: last_readings,
      meters: meters
    ))

    expect(page).to have_field("meter_readings[1]")
    expect(page).to have_text("Last reading: 12,487 kWh (Feb 15)")
    expect(page).to have_field("meter_readings[2]")
    expect(page).to have_text("Last reading: 3,219 kWh (Feb 15)")
  end

  it "renders note field" do
    render_inline(described_class.new(
      visitors: [ visitor ],
      last_readings: last_readings,
      meters: meters
    ))

    expect(page).to have_field("note")
  end
end
