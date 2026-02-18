# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::VisitorCardComponent, type: :component do
  it "renders visitor name and check-in date" do
    visitor = instance_double("Visitor", name: "Alice")
    checked_in_at = 2.days.ago

    render_inline(described_class.new(visitor: visitor, checked_in_at: checked_in_at, stay_id: 1))

    expect(page).to have_css(".bg-blue-50.rounded-lg")
    expect(page).to have_text("Alice")
    expect(page).to have_text("since")
    expect(page).to have_button("Check out")
  end

  it "renders check-out button with icon" do
    visitor = instance_double("Visitor", name: "Bob")
    checked_in_at = 1.day.ago

    render_inline(described_class.new(visitor: visitor, checked_in_at: checked_in_at, stay_id: 2))

    expect(page).to have_button("Check out")
    expect(page).to have_css("i.fa-solid.fa-right-from-bracket")
  end

  it "renders recently when no check-in date" do
    visitor = instance_double("Visitor", name: "Carol")

    render_inline(described_class.new(visitor: visitor, checked_in_at: nil, stay_id: 3))

    expect(page).to have_text("Carol")
    expect(page).to have_text("recently")
  end
end
