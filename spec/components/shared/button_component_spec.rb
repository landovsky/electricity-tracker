# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::ButtonComponent, type: :component do
  it "renders primary button by default" do
    render_inline(described_class.new(label: "Submit"))

    expect(page).to have_button("Submit")
    expect(page).to have_css("button.bg-brand-600.text-white")
  end

  it "renders secondary button variant" do
    render_inline(described_class.new(label: "Cancel", variant: "secondary"))

    expect(page).to have_button("Cancel")
    expect(page).to have_css("button.bg-white.border.border-gray-200")
  end

  it "renders danger button variant" do
    render_inline(described_class.new(label: "Delete", variant: "danger"))

    expect(page).to have_button("Delete")
    expect(page).to have_css("button.bg-red-600.text-white")
  end

  it "renders as link when url is provided" do
    render_inline(described_class.new(label: "View All", url: "/readings_history"))

    expect(page).to have_link("View All", href: "/readings_history")
  end

  it "applies correct method to link" do
    render_inline(described_class.new(label: "Delete", url: "/items/1", method: :delete, variant: "danger"))

    expect(page).to have_link("Delete", href: "/items/1")
    expect(page).to have_css('a[data-turbo-method="delete"]')
  end
end
