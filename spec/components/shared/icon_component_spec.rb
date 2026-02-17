# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::IconComponent, type: :component do
  it "renders icon with solid style by default" do
    render_inline(described_class.new(icon_class: "fa-house"))

    expect(page).to have_css("i.fa-solid.fa-house")
  end

  it "renders icon with duotone style when specified" do
    render_inline(described_class.new(icon_class: "fa-bolt", style: "duotone"))

    expect(page).to have_css("i.fa-duotone.fa-bolt")
  end

  it "applies color class when provided" do
    render_inline(described_class.new(icon_class: "fa-check", color: "text-green-500"))

    expect(page).to have_css("i.fa-solid.fa-check.text-green-500")
  end

  it "does not apply color class when not provided" do
    render_inline(described_class.new(icon_class: "fa-check"))

    expect(page).to have_css("i.fa-solid.fa-check")
    expect(page).not_to have_css("i.text-green-500")
  end
end
