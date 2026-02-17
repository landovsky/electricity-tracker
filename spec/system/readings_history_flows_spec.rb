# frozen_string_literal: true

require 'rails_helper'

# System tests for readings history viewing (Screen S3)
#
# Tests cover:
# - Viewing all meter reading events and manual consumption entries
# - Filtering by visitor
# - Filtering by date range
# - Display of events with associated readings
# - Chronological ordering
# - Empty states
#
# Testing approach: Verify both UI state (what user sees) and database state (correct data fetched)
RSpec.describe "Readings History Flows", type: :system do
  let!(:property) { create(:property) }
  let!(:main_meter) { create(:meter, :main, property: property) }
  let!(:secondary_meter) { create(:meter, :secondary, property: property) }
  let!(:alice) { create(:visitor, name: "Alice") }
  let!(:bob) { create(:visitor, name: "Bob") }
  let!(:user) { create(:user) }

  scenario "View all meter readings history" do
    # Create multiple readings across different dates
    stay1 = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 5.days.ago,
      check_out_at: 3.days.ago,
      main_reading_in: 1000.0,
      secondary_reading_in: 500.0,
      main_reading_out: 1050.0,
      secondary_reading_out: 525.0,
      recorded_by: user
    )

    stay2 = create(:stay, :closed,
      visitor: bob,
      property: property,
      check_in_at: 2.days.ago,
      check_out_at: 1.day.ago,
      main_reading_in: 1050.0,
      secondary_reading_in: 525.0,
      main_reading_out: 1100.0,
      secondary_reading_out: 550.0,
      recorded_by: user
    )

    # Create manual consumption entries
    manual_entry1 = create(:manual_consumption_entry,
      visitor: alice,
      property: property,
      date: 6.days.ago.to_date,
      kwh: 25.5,
      note: "Baseline adjustment",
      recorded_by_user: user
    )

    manual_entry2 = create(:manual_consumption_entry,
      visitor: bob,
      property: property,
      date: 4.days.ago.to_date,
      kwh: 15.0,
      note: "Estimated usage",
      recorded_by_user: user
    )

    visit_readings_history

    # UI State: Verify page loaded and shows all events
    expect(page).to have_content("Readings History")
    expect(page).to have_content("Meter Reading Events")
    expect(page).to have_content("Manual Consumption Entries")

    # Verify meter reading events are displayed
    expect(page).to have_content("Alice")
    expect(page).to have_content("Bob")
    expect(page).to have_content(I18n.t("history.checked_in"))
    expect(page).to have_content(I18n.t("history.checked_out"))

    # Verify meter readings are shown with correct labels and values
    expect(page).to have_content("Main meter: 1000.00 kWh")
    expect(page).to have_content("Main meter: 1050.00 kWh")
    expect(page).to have_content("Main meter: 1100.00 kWh")
    expect(page).to have_content("Upper floor meter: 500.00 kWh")
    expect(page).to have_content("Upper floor meter: 525.00 kWh")
    expect(page).to have_content("Upper floor meter: 550.00 kWh")

    # Verify manual consumption entries are displayed
    expect(page).to have_content("Baseline adjustment")
    expect(page).to have_content("Estimated usage")
    expect(page).to have_content("25.50")
    expect(page).to have_content("15.00")

    # Database State: Verify correct number of events fetched
    expect(MeterReadingEvent.kept.count).to eq(4) # 2 check-ins + 2 check-outs
    expect(ManualConsumptionEntry.count).to eq(2)
  end

  scenario "Filter by visitor" do
    # Create readings for multiple visitors
    alice_stay = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 3.days.ago,
      check_out_at: 1.day.ago,
      main_reading_in: 1000.0,
      secondary_reading_in: 500.0,
      main_reading_out: 1050.0,
      secondary_reading_out: 525.0,
      recorded_by: user
    )

    bob_stay = create(:stay, :closed,
      visitor: bob,
      property: property,
      check_in_at: 2.days.ago,
      check_out_at: 1.day.ago,
      main_reading_in: 1050.0,
      secondary_reading_in: 525.0,
      main_reading_out: 1100.0,
      secondary_reading_out: 550.0,
      recorded_by: user
    )

    alice_manual = create(:manual_consumption_entry,
      visitor: alice,
      property: property,
      date: 4.days.ago.to_date,
      kwh: 20.0,
      recorded_by_user: user
    )

    bob_manual = create(:manual_consumption_entry,
      visitor: bob,
      property: property,
      date: 3.days.ago.to_date,
      kwh: 15.0,
      recorded_by_user: user
    )

    visit_readings_history

    # Filter by Alice
    select "Alice", from: "visitor_id"
    click_button "Filter"

    # UI State: Only Alice's events should be visible in the meter reading events section
    meter_events_section = page.find("h2", text: "Meter Reading Events").find(:xpath, "following-sibling::table[1]")
    within(meter_events_section) do
      expect(page).to have_content("Alice")
      expect(page).not_to have_content("Bob")
    end

    # Verify Alice's meter readings are shown
    expect(page).to have_content("Main meter: 1000.00 kWh")
    expect(page).to have_content("Main meter: 1050.00 kWh")

    # Verify Alice's manual entry is shown
    expect(page).to have_content("20.00")

    # Bob's readings should not appear
    expect(page).not_to have_content("Main meter: 1100.00 kWh")
    expect(page).not_to have_content("15.00")

    # Database State: Verify correct filtering
    # Alice has 2 events (check-in + check-out)
    alice_events = MeterReadingEvent.joins("LEFT JOIN stays AS check_in_stays ON meter_reading_events.id = check_in_stays.check_in_event_id")
                                    .joins("LEFT JOIN stays AS check_out_stays ON meter_reading_events.id = check_out_stays.check_out_event_id")
                                    .where("check_in_stays.visitor_id = ? OR check_out_stays.visitor_id = ?", alice.id, alice.id)
    expect(alice_events.count).to eq(2)

    # Alice has 1 manual entry
    alice_manual_entries = ManualConsumptionEntry.where(visitor_id: alice.id)
    expect(alice_manual_entries.count).to eq(1)
  end

  scenario "Filter by date range" do
    # Create readings across different dates
    old_stay = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 10.days.ago,
      check_out_at: 8.days.ago,
      main_reading_in: 900.0,
      secondary_reading_in: 450.0,
      main_reading_out: 950.0,
      secondary_reading_out: 475.0,
      recorded_by: user
    )

    recent_stay = create(:stay, :closed,
      visitor: bob,
      property: property,
      check_in_at: 2.days.ago,
      check_out_at: 1.day.ago,
      main_reading_in: 1000.0,
      secondary_reading_in: 500.0,
      main_reading_out: 1050.0,
      secondary_reading_out: 525.0,
      recorded_by: user
    )

    old_manual = create(:manual_consumption_entry,
      visitor: alice,
      property: property,
      date: 12.days.ago.to_date,
      kwh: 30.0,
      recorded_by_user: user
    )

    recent_manual = create(:manual_consumption_entry,
      visitor: bob,
      property: property,
      date: 3.days.ago.to_date,
      kwh: 20.0,
      recorded_by_user: user
    )

    visit_readings_history

    # Filter by date range (last 5 days)
    fill_in "start_date", with: 5.days.ago.to_date.strftime("%Y-%m-%d")
    fill_in "end_date", with: Date.current.strftime("%Y-%m-%d")
    click_button "Filter"

    # UI State: Only recent events should be visible in the meter reading events section
    meter_events_section = page.find("h2", text: "Meter Reading Events").find(:xpath, "following-sibling::table[1]")
    within(meter_events_section) do
      expect(page).to have_content("Bob")
      expect(page).not_to have_content("Alice")
    end

    # Verify recent readings are shown
    expect(page).to have_content("Main meter: 1000.00 kWh")
    expect(page).to have_content("Main meter: 1050.00 kWh")

    # Old readings should not appear
    expect(page).not_to have_content("Main meter: 900.00 kWh")
    expect(page).not_to have_content("Main meter: 950.00 kWh")

    # Database State: Verify correct date filtering
    start_date = 5.days.ago.to_date
    end_date = Date.current

    recent_events = MeterReadingEvent.where("DATE(recorded_at) >= ? AND DATE(recorded_at) <= ?", start_date, end_date)
    expect(recent_events.count).to eq(2) # Bob's check-in and check-out

    recent_manual_entries = ManualConsumptionEntry.where("date >= ? AND date <= ?", start_date, end_date)
    expect(recent_manual_entries.count).to eq(1) # Bob's manual entry
  end

  scenario "Display shows events (check-in/check-out) with readings" do
    # Create a stay with both check-in and check-out
    stay = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 3.days.ago,
      check_out_at: 1.day.ago,
      main_reading_in: 1000.0,
      secondary_reading_in: 500.0,
      main_reading_out: 1080.0,
      secondary_reading_out: 540.0,
      recorded_by: user
    )

    visit_readings_history

    # UI State: Verify both check-in and check-out events are displayed
    expect(page).to have_content(I18n.t("history.checked_in"))
    expect(page).to have_content(I18n.t("history.checked_out"))

    # Verify check-in readings
    expect(page).to have_content("Main meter: 1000.00 kWh")
    expect(page).to have_content("Upper floor meter: 500.00 kWh")

    # Verify check-out readings
    expect(page).to have_content("Main meter: 1080.00 kWh")
    expect(page).to have_content("Upper floor meter: 540.00 kWh")

    # Verify visitor is associated with both events
    within("table") do
      expect(page).to have_content("Alice", count: 2) # Once for check-in, once for check-out
    end

    # Database State: Verify events are properly associated with readings
    check_in_event = stay.check_in_event
    check_out_event = stay.check_out_event

    expect(check_in_event).to be_present
    expect(check_out_event).to be_present

    # Check-in event has 2 readings (main + secondary)
    expect(check_in_event.meter_readings.count).to eq(2)
    expect(check_in_event.meter_readings.find_by(meter: main_meter).value_kwh).to eq(1000.0)
    expect(check_in_event.meter_readings.find_by(meter: secondary_meter).value_kwh).to eq(500.0)

    # Check-out event has 2 readings (main + secondary)
    expect(check_out_event.meter_readings.count).to eq(2)
    expect(check_out_event.meter_readings.find_by(meter: main_meter).value_kwh).to eq(1080.0)
    expect(check_out_event.meter_readings.find_by(meter: secondary_meter).value_kwh).to eq(540.0)
  end

  scenario "Readings sorted chronologically (most recent first)" do
    # Create readings in chronological order to respect monotonic constraint,
    # but create them in code in non-chronological order to test sorting
    oldest_stay = create(:stay, :closed,
      visitor: bob,
      property: property,
      check_in_at: 5.days.ago,
      check_out_at: 4.days.ago,
      main_reading_in: 900.0,
      secondary_reading_in: 450.0,
      main_reading_out: 950.0,
      secondary_reading_out: 475.0,
      recorded_by: user
    )

    middle_stay = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 3.days.ago,
      check_out_at: 2.days.ago,
      main_reading_in: 1000.0,
      secondary_reading_in: 500.0,
      main_reading_out: 1050.0,
      secondary_reading_out: 525.0,
      recorded_by: user
    )

    newest_stay = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 1.day.ago,
      check_out_at: Time.current,
      main_reading_in: 1075.0,
      secondary_reading_in: 537.5,
      main_reading_out: 1100.0,
      secondary_reading_out: 550.0,
      recorded_by: user
    )

    visit_readings_history

    # UI State: Verify events are displayed in descending chronological order (most recent first)
    # Extract all event rows and check their order
    event_table = find("table", match: :first)
    rows = event_table.all("tbody tr")

    # Most recent event should be first (newest check-out)
    expect(rows[0]).to have_content("1100.00")

    # Oldest event should be last (oldest check-in)
    last_row_index = rows.length - 1
    expect(rows[last_row_index]).to have_content("900.00")

    # Database State: Verify query sorts by recorded_at DESC
    events = MeterReadingEvent.order(recorded_at: :desc)
    expect(events.first.recorded_at).to be > events.last.recorded_at
    expect(events.first.meter_readings.find_by(meter: main_meter).value_kwh).to eq(1100.0) # Most recent
    expect(events.last.meter_readings.find_by(meter: main_meter).value_kwh).to eq(900.0) # Oldest
  end

  scenario "Empty state when no readings exist" do
    # Don't create any readings

    visit_readings_history

    # UI State: Verify empty state message
    expect(page).to have_content("Readings History")
    expect(page).to have_content("No readings history found for the selected filters")

    # Database State: Verify no events exist
    expect(MeterReadingEvent.kept.count).to eq(0)
    expect(ManualConsumptionEntry.count).to eq(0)
  end

  scenario "Empty state when filters match no results" do
    # Create some readings
    stay = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 5.days.ago,
      check_out_at: 3.days.ago,
      main_reading_in: 1000.0,
      secondary_reading_in: 500.0,
      main_reading_out: 1050.0,
      secondary_reading_out: 525.0,
      recorded_by: user
    )

    visit_readings_history

    # Filter by Bob (who has no readings)
    select "Bob", from: "visitor_id"
    click_button "Filter"

    # UI State: Verify empty state for filtered results
    expect(page).to have_content("No readings history found for the selected filters")

    # Verify filter form is still visible
    expect(page).to have_select("visitor_id", selected: "Bob")
  end

  scenario "Combined filters (visitor and date range)" do
    # Create readings for multiple visitors across different dates
    alice_old = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 10.days.ago,
      check_out_at: 8.days.ago,
      main_reading_in: 900.0,
      secondary_reading_in: 450.0,
      main_reading_out: 950.0,
      secondary_reading_out: 475.0,
      recorded_by: user
    )

    alice_recent = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 2.days.ago,
      check_out_at: 1.day.ago,
      main_reading_in: 1000.0,
      secondary_reading_in: 500.0,
      main_reading_out: 1050.0,
      secondary_reading_out: 525.0,
      recorded_by: user
    )

    bob_recent = create(:stay, :closed,
      visitor: bob,
      property: property,
      check_in_at: 3.days.ago,
      check_out_at: 2.days.ago,
      main_reading_in: 1050.0,
      secondary_reading_in: 525.0,
      main_reading_out: 1100.0,
      secondary_reading_out: 550.0,
      recorded_by: user
    )

    visit_readings_history

    # Filter by Alice AND date range (last 5 days)
    select "Alice", from: "visitor_id"
    fill_in "start_date", with: 5.days.ago.to_date.strftime("%Y-%m-%d")
    fill_in "end_date", with: Date.current.strftime("%Y-%m-%d")
    click_button "Filter"

    # UI State: Only Alice's recent events should be visible in the results
    within("table") do
      expect(page).to have_content("Alice")
      expect(page).not_to have_content("Bob")
    end

    # Alice's recent readings (1000, 1050)
    expect(page).to have_content("Main meter: 1000.00 kWh")
    expect(page).to have_content("Main meter: 1050.00 kWh")

    # Alice's old readings should not appear (900, 950)
    expect(page).not_to have_content("Main meter: 900.00 kWh")
    expect(page).not_to have_content("Main meter: 950.00 kWh")

    # Bob's readings should not appear (1100)
    expect(page).not_to have_content("Main meter: 1100.00 kWh")

    # Database State: Verify combined filtering
    start_date = 5.days.ago.to_date
    end_date = Date.current

    alice_recent_events = MeterReadingEvent.joins("LEFT JOIN stays AS check_in_stays ON meter_reading_events.id = check_in_stays.check_in_event_id")
                                           .joins("LEFT JOIN stays AS check_out_stays ON meter_reading_events.id = check_out_stays.check_out_event_id")
                                           .where("check_in_stays.visitor_id = ? OR check_out_stays.visitor_id = ?", alice.id, alice.id)
                                           .where("DATE(recorded_at) >= ? AND DATE(recorded_at) <= ?", start_date, end_date)
    expect(alice_recent_events.count).to eq(2) # Alice's recent check-in and check-out
  end

  scenario "Manual consumption entries are included in history" do
    # Create only manual consumption entries (no meter reading events)
    manual1 = create(:manual_consumption_entry,
      visitor: alice,
      property: property,
      date: 3.days.ago.to_date,
      kwh: 25.5,
      note: "Estimated usage for Alice",
      recorded_by_user: user
    )

    manual2 = create(:manual_consumption_entry,
      visitor: bob,
      property: property,
      date: 2.days.ago.to_date,
      kwh: 15.0,
      note: "Baseline adjustment for Bob",
      recorded_by_user: user
    )

    visit_readings_history

    # UI State: Verify manual entries are displayed
    expect(page).to have_content("Manual Consumption Entries")
    expect(page).to have_content("Alice")
    expect(page).to have_content("Bob")
    expect(page).to have_content("25.50")
    expect(page).to have_content("15.00")
    expect(page).to have_content("Estimated usage for Alice")
    expect(page).to have_content("Baseline adjustment for Bob")

    # Database State: Verify manual entries exist
    expect(ManualConsumptionEntry.count).to eq(2)
  end

  scenario "Clear filters to show all readings" do
    # Create readings with different visitors and dates
    alice_stay = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 3.days.ago,
      check_out_at: 1.day.ago,
      main_reading_in: 1000.0,
      secondary_reading_in: 500.0,
      main_reading_out: 1050.0,
      secondary_reading_out: 525.0,
      recorded_by: user
    )

    bob_stay = create(:stay, :closed,
      visitor: bob,
      property: property,
      check_in_at: 2.days.ago,
      check_out_at: 1.day.ago,
      main_reading_in: 1050.0,
      secondary_reading_in: 525.0,
      main_reading_out: 1100.0,
      secondary_reading_out: 550.0,
      recorded_by: user
    )

    visit_readings_history

    # Apply filter
    select "Alice", from: "visitor_id"
    click_button "Filter"

    # Verify only Alice is shown in the results
    within("table") do
      expect(page).to have_content("Alice")
      expect(page).not_to have_content("Bob")
    end

    # Clear filter by selecting "All Visitors"
    select "All Visitors", from: "visitor_id"
    click_button "Filter"

    # UI State: Both visitors should now be visible in the results
    within("table") do
      expect(page).to have_content("Alice")
      expect(page).to have_content("Bob")
    end

    # Verify all readings are shown
    expect(page).to have_content("Main meter: 1000.00 kWh")
    expect(page).to have_content("Main meter: 1050.00 kWh")
    expect(page).to have_content("Main meter: 1100.00 kWh")
  end
end
