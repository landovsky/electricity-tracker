# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::MeterReadingCardComponent, type: :component do
  it "renders meter reading with formatted value" do
    date = Date.parse("2026-02-15")
    render_inline(described_class.new(label: "Main meter", value: 12_487, date: date, icon_class: "fa-gauge-high"))

    expect(page).to have_css(".bg-gray-50.rounded-lg")
    expect(page).to have_text("Main meter")
    expect(page).to have_text("12,487")
    expect(page).to have_text("kWh")
    expect(page).to have_text("Feb 15")
  end

  it "renders icon" do
    date = Date.parse("2026-02-15")
    render_inline(described_class.new(label: "Main meter", value: 12_487, date: date, icon_class: "fa-gauge-high"))

    expect(page).to have_css("i.fa-solid.fa-gauge-high")
  end

  it "uses default icon when not specified" do
    date = Date.parse("2026-02-15")
    render_inline(described_class.new(label: "Main meter", value: 12_487, date: date))

    expect(page).to have_css("i.fa-solid.fa-gauge-high")
  end
end
