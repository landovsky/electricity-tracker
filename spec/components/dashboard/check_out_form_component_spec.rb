# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::CheckOutFormComponent, type: :component do
  let(:event) { instance_double("Event", recorded_at: 2.days.ago) }
  let(:stay) { instance_double("Stay", id: 1, open?: true, check_in_event: event) }
  let(:visitor) { instance_double("Visitor", id: 1, name: "Alice", stays: [stay]) }
  let(:main_meter) { instance_double("Meter", id: 1, meter_type: "main", label: "Main meter") }
  let(:meters) { [main_meter] }
  let(:last_readings) do
    {
      "main" => { value: 12_487, date: Date.parse("2026-02-15") }
    }
  end

  it "renders check-out form with visitor select" do
    render_inline(described_class.new(
      current_visitors: [visitor],
      last_readings: last_readings,
      meters: meters
    ))

    expect(page).to have_select("stay_id")
    expect(page).to have_field("recorded_at")
    expect(page).to have_button("Check Out")
  end

  it "renders meter reading fields" do
    render_inline(described_class.new(
      current_visitors: [visitor],
      last_readings: last_readings,
      meters: meters
    ))

    expect(page).to have_field("main_meter_reading")
    expect(page).to have_text("Last reading: 12,487 kWh (Feb 15)")
  end

  it "renders empty state when no current visitors" do
    render_inline(described_class.new(
      current_visitors: [],
      last_readings: last_readings,
      meters: meters
    ))

    expect(page).to have_text("No visitors to check out.")
  end
end
