# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::ActionFormsComponent, type: :component do
  let(:visitor) { instance_double("Visitor", id: 1, name: "Alice") }
  let(:main_meter) { instance_double("Meter", id: 1, meter_type: "main", label: "Main meter") }
  let(:meters) { [ main_meter ] }
  let(:last_readings) do
    {
      "main" => { value: 12_487, date: Date.parse("2026-02-15") }
    }
  end

  it "renders tabbed container with three tab buttons" do
    render_inline(described_class.new(
      visitors_for_checkin: [ visitor ],
      visitors_for_checkout: [],
      meters: meters,
      last_readings: last_readings
    ))

    expect(page).to have_button("Check In")
    expect(page).to have_button("Check Out")
    expect(page).to have_button("Log Entry")
  end

  it "renders all three form components" do
    render_inline(described_class.new(
      visitors_for_checkin: [ visitor ],
      visitors_for_checkout: [],
      meters: meters,
      last_readings: last_readings
    ))

    # Check-in form is visible by default
    expect(page).to have_select("visitor_id")

    # Forms are present (even if hidden)
    expect(page).to have_css("button[type='submit']", minimum: 1)
  end

  it "shows check-in tab as active" do
    render_inline(described_class.new(
      visitors_for_checkin: [ visitor ],
      visitors_for_checkout: [],
      meters: meters,
      last_readings: last_readings
    ))

    # Check-in tab should have active styling (emerald color)
    expect(page).to have_css("button.border-emerald-600.text-emerald-700.bg-emerald-50", text: "Check In")
  end
end
