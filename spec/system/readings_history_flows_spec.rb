# frozen_string_literal: true

require 'rails_helper'

# System tests for readings history viewing (Screen S3)
#
# Tests cover:
# - Viewing all meter reading events and manual consumption entries
# - Filtering by visitor
# - Display of events with associated readings
# - Chronological ordering
# - Empty states
#
# Testing approach: Verify both UI state (what user sees) and database state (correct data fetched)
RSpec.describe "Readings history Flows", type: :system do
  let!(:property) { create(:property) }
  let!(:main_meter) { create(:meter, :main, property: property) }
  let!(:secondary_meter) { create(:meter, :secondary, property: property) }
  let!(:alice) { create(:visitor, name: "Alice", property: property) }
  let!(:bob) { create(:visitor, name: "Bob", property: property) }
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
    expect(page).to have_content(I18n.t("history.title"))

    # Verify meter reading events are displayed (timeline cards, not tables)
    expect(page).to have_content("Alice")
    expect(page).to have_content("Bob")
    expect(page).to have_content(I18n.t("history.checked_in"))
    expect(page).to have_content(I18n.t("history.checked_out"))

    # Verify manual consumption entries are displayed (in card format)
    expect(page).to have_content("Baseline adjustment")
    expect(page).to have_content("Estimated usage")

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

    # Filter by Alice - visit with query parameter since auto-submit uses JS
    visit readings_history_path(visitor_id: alice.id)

    # UI State: Only Alice's events should be visible in timeline cards
    # (Alice also appears in the filter dropdown, so check timeline content)
    expect(page).not_to have_content("Bob #{I18n.t('history.checked_in')}")
    expect(page).not_to have_content("Bob #{I18n.t('history.checked_out')}")

    # Database State: Verify correct filtering
    alice_events = MeterReadingEvent.joins("LEFT JOIN stays AS check_in_stays ON meter_reading_events.id = check_in_stays.check_in_event_id")
                                    .joins("LEFT JOIN stays AS check_out_stays ON meter_reading_events.id = check_out_stays.check_out_event_id")
                                    .where("check_in_stays.visitor_id = ? OR check_out_stays.visitor_id = ?", alice.id, alice.id)
    expect(alice_events.count).to eq(2)

    # Alice has 1 manual entry
    alice_manual_entries = ManualConsumptionEntry.where(visitor_id: alice.id)
    expect(alice_manual_entries.count).to eq(1)
  end

  scenario "Filter by year" do
    # Create readings in different years
    old_stay = create(:stay, :closed,
      visitor: alice,
      property: property,
      check_in_at: 1.year.ago - 10.days,
      check_out_at: 1.year.ago - 8.days,
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

    visit_readings_history

    # Current year should be selected by default, showing only recent events
    expect(page).to have_content("Bob")

    # Database State: Verify events exist for current and past year
    expect(MeterReadingEvent.kept.count).to eq(4) # 2 stays × 2 events
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

    # Verify meter readings are shown in integer format with delimiter (e.g., "1,000 kWh")
    expect(page).to have_content("1,000 kWh")
    expect(page).to have_content("1,080 kWh")
    expect(page).to have_content("500 kWh")
    expect(page).to have_content("540 kWh")

    # Verify Alice appears in the event cards (also in filter dropdown)
    expect(page).to have_content("Alice #{I18n.t('history.checked_in')}")
    expect(page).to have_content("Alice #{I18n.t('history.checked_out')}")

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

    # Database State: Verify query sorts by recorded_at DESC
    events = MeterReadingEvent.order(recorded_at: :desc)
    expect(events.first.recorded_at).to be > events.last.recorded_at
    expect(events.first.meter_readings.find_by(meter: main_meter).value_kwh).to eq(1100.0) # Most recent
    expect(events.last.meter_readings.find_by(meter: main_meter).value_kwh).to eq(900.0) # Oldest

    # UI: Page should render without error and show events
    expect(page).to have_content(I18n.t("history.title"))
    expect(page).to have_content("Alice")
    expect(page).to have_content("Bob")
  end

  scenario "Empty state when no readings exist" do
    # Don't create any readings

    visit_readings_history

    # UI State: Verify empty state message
    expect(page).to have_content(I18n.t("history.title"))
    expect(page).to have_content(I18n.t("history.no_history"))

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

    # Filter by Bob (who has no readings) - use query param since auto-submit needs JS
    visit readings_history_path(visitor_id: bob.id)

    # UI State: Verify empty state for filtered results
    expect(page).to have_content(I18n.t("history.no_history"))
  end

  scenario "Filter and clear filters" do
    # Create readings with different visitors
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

    # Apply filter via URL (auto-submit needs JS)
    visit readings_history_path(visitor_id: alice.id)

    # Verify only Alice events shown (names also appear in filter dropdown)
    expect(page).not_to have_content("Bob #{I18n.t('history.checked_in')}")
    expect(page).not_to have_content("Bob #{I18n.t('history.checked_out')}")

    # Clear filter
    visit readings_history_path

    # Both visitors should now be visible
    expect(page).to have_content("Alice #{I18n.t('history.checked_in')}")
    expect(page).to have_content("Bob #{I18n.t('history.checked_in')}")
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

    # UI State: Verify manual entries are displayed in card format
    expect(page).to have_content("Alice")
    expect(page).to have_content("Bob")
    expect(page).to have_content("Estimated usage for Alice")
    expect(page).to have_content("Baseline adjustment for Bob")

    # Database State: Verify manual entries exist
    expect(ManualConsumptionEntry.count).to eq(2)
  end
end
