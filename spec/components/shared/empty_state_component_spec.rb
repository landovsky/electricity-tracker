# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::EmptyStateComponent, type: :component do
  it "renders empty state message" do
    render_inline(described_class.new(message: "No items found"))

    expect(page).to have_css("div.text-gray-400.italic", text: "No items found")
  end

  it "renders with icon when icon_class is provided" do
    render_inline(described_class.new(message: "No visitors", icon_class: "fa-users"))

    expect(page).to have_css("i.fa-solid.fa-users.text-gray-400")
    expect(page).to have_text("No visitors")
  end

  it "does not render icon when icon_class is not provided" do
    render_inline(described_class.new(message: "No visitors"))

    expect(page).not_to have_css("i")
    expect(page).to have_text("No visitors")
  end
end
