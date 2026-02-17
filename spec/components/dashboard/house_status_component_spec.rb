# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::HouseStatusComponent, type: :component do
  let(:event) { instance_double("Event", recorded_at: 2.days.ago) }
  let(:stay) { instance_double("Stay", open?: true, check_in_event: event) }
  let(:visitor) { instance_double("Visitor", name: "Alice", stays: [ stay ]) }

  let(:last_meter_readings) do
    {
      "main" => { label: "Main meter", value: 12_487, date: Date.parse("2026-02-15") },
      "secondary" => { label: "Upper floor", value: 3_219, date: Date.parse("2026-02-15") }
    }
  end

  it "renders house status with current visitors" do
    render_inline(described_class.new(
      current_visitors: [ visitor ],
      last_meter_readings: last_meter_readings
    ))

    expect(page).to have_css("h2", text: I18n.t("dashboard.house_status.title"))
    expect(page).to have_text(I18n.t("dashboard.house_status.currently_here"))
    expect(page).to have_text("Alice")
  end

  it "renders empty state when no visitors" do
    render_inline(described_class.new(
      current_visitors: [],
      last_meter_readings: last_meter_readings
    ))

    expect(page).to have_text(I18n.t("dashboard.house_status.nobody_here"))
  end

  it "renders meter readings" do
    render_inline(described_class.new(
      current_visitors: [],
      last_meter_readings: last_meter_readings
    ))

    expect(page).to have_text("Latest meter readings")
    expect(page).to have_text("Main meter")
    expect(page).to have_text("12,487")
    expect(page).to have_text("Upper floor")
    expect(page).to have_text("3,219")
  end

  it "renders empty state when no meter readings" do
    render_inline(described_class.new(
      current_visitors: [],
      last_meter_readings: {}
    ))

    expect(page).to have_text("No meter readings recorded yet.")
  end
end
