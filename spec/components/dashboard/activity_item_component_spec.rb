# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::ActivityItemComponent, type: :component do
  it "renders check-in activity with green icon" do
    render_inline(described_class.new(
      type: "check_in",
      visitor_name: "Alice",
      action: "checked in",
      date: Date.parse("2026-02-15"),
      details: "Main: 12,487"
    ))

    expect(page).to have_css("i.fa-solid.fa-right-to-bracket.text-green-500")
    expect(page).to have_css("span.font-medium", text: "Alice")
    expect(page).to have_text("checked in")
    expect(page).to have_text("Feb 15")
    expect(page).to have_text("Main: 12,487")
  end

  it "renders check-out activity with red icon" do
    render_inline(described_class.new(
      type: "check_out",
      visitor_name: "Bob",
      action: "checked out",
      date: Date.parse("2026-02-14")
    ))

    expect(page).to have_css("i.fa-solid.fa-right-from-bracket.text-red-400")
    expect(page).to have_css("span.font-medium", text: "Bob")
    expect(page).to have_text("checked out")
  end

  it "renders manual entry activity with yellow icon" do
    render_inline(described_class.new(
      type: "manual_entry",
      visitor_name: "Carol",
      action: "logged 15 kWh",
      date: Date.parse("2026-02-13"),
      details: "EV charging"
    ))

    expect(page).to have_css("i.fa-solid.fa-bolt.text-yellow-500")
    expect(page).to have_css("span.font-medium", text: "Carol")
    expect(page).to have_text("logged 15 kWh")
    expect(page).to have_text("EV charging")
  end

  it "does not render details when not provided" do
    render_inline(described_class.new(
      type: "check_in",
      visitor_name: "Dave",
      action: "checked in",
      date: Date.parse("2026-02-12")
    ))

    expect(page).to have_css("span.font-medium", text: "Dave")
    expect(page).not_to have_css("div.ml-5")
  end
end
