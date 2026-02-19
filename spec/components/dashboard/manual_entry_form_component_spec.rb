# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::ManualEntryFormComponent, type: :component do
  let(:visitor) { instance_double("Visitor", id: 1, name: "Alice") }

  it "renders manual entry form with visitor select" do
    render_inline(described_class.new(visitors: [ visitor ]))

    expect(page).to have_select("visitor_id")
    expect(page).to have_field("date")
    expect(page).to have_field("kwh")
    expect(page).to have_field("note")
    expect(page).to have_button("Log Entry")
  end

  it "renders required field indicators" do
    render_inline(described_class.new(visitors: [ visitor ]))

    expect(page).to have_css("span.text-red-500", text: "*", count: 2) # kwh and note
  end

  it "renders kWh unit label" do
    render_inline(described_class.new(visitors: [ visitor ]))

    expect(page).to have_text("kWh")
  end
end
