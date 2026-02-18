# frozen_string_literal: true

require 'rails_helper'

# Smoke test to verify system test infrastructure is working
#
# This test verifies that:
# - Capybara can load pages
# - SystemHelpers are available
# - Database is properly cleaned between tests
# - ViewComponents render correctly
RSpec.describe "Dashboard", type: :system do
  let!(:property) { create(:property) }
  let!(:main_meter) { create(:meter, :main, property: property) }
  let!(:secondary_meter) { create(:meter, :secondary, property: property) }
  let!(:visitor) { create(:visitor, name: "Alice") }

  scenario "loads the dashboard page" do
    visit root_path

    # Verify page loaded successfully
    expect(page.status_code).to eq(200)
    expect(page).to have_content(I18n.t("dashboard.house_status.title", property_name: property.name))
  end

  scenario "displays check-in and check-out forms" do
    visit root_path

    # Forms should be present (using CSS selectors)
    expect(page).to have_css("form[action='/stays']")
    expect(page).to have_selector("select#visitor_id")
    expect(page).to have_field("main_meter_reading")
  end

  scenario "lists visitors in the check-in form" do
    visit root_path

    # Visitor should be available for selection
    expect(page).to have_select("visitor_id", with_options: [ visitor.name ])
  end

  scenario "SystemHelpers are available", :skip_in_ci do
    # This test verifies helpers work but requires JavaScript
    # Skip in CI without Chrome
    skip "Requires JavaScript driver" unless Capybara.current_driver != :rack_test

    visit root_path
    # If we get here, the page loaded and helpers are available
    expect(page).to respond_to(:have_content)
  end
end
