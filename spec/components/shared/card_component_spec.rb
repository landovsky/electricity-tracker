# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::CardComponent, type: :component do
  it "renders card with title and content" do
    render_inline(described_class.new(title: "House Status")) { "<p>Content here</p>".html_safe }

    expect(page).to have_css("section.bg-white.rounded-xl.shadow-sm")
    expect(page).to have_css("h2", text: "House Status")
    expect(page).to have_css("p", text: "Content here")
  end

  it "renders header action when provided" do
    header_action = '<a href="/readings_history" class="text-brand-600">View all</a>'
    render_inline(described_class.new(title: "Recent Activity", header_action: header_action)) { "Content" }

    expect(page).to have_link("View all", href: "/readings_history")
    expect(page).to have_css(".flex.items-center.justify-between")
  end

  it "does not render flex classes when no header action" do
    render_inline(described_class.new(title: "House Status")) { "Content" }

    expect(page).not_to have_css(".flex.items-center.justify-between")
  end
end
