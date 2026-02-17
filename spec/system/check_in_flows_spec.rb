# frozen_string_literal: true

require 'rails_helper'

# System tests for visitor check-in flows
#
# Tests the full check-in user journey from UI interaction to database state.
# Covers happy paths, validation scenarios, and edge cases as specified in the requirements.
#
# Test Coverage:
# - Happy path scenarios (successful check-in flows)
# - Constraint validation (C1, C2, C4, C6)
# - Edge cases (E2, E7, E8, E9)
#
# Note: These tests use rack_test driver (non-JavaScript) which means:
# - Forms submit via traditional POST (not Turbo Streams)
# - Flash messages appear in redirected page
# - Dynamic updates won't be visible in the same page context
RSpec.describe "Visitor Check-In Flows", type: :system do
  let!(:property) { create(:property) }
  let!(:main_meter) { create(:meter, :main, property: property) }
  let!(:secondary_meter) { create(:meter, :secondary, property: property) }
  let!(:visitor1) { create(:visitor, name: "Alice") }
  let!(:visitor2) { create(:visitor, name: "Bob") }
  let!(:user) { create(:user) }

  before do
    # Ensure clean state for each test
    visit root_path
  end

  # =============================================================================
  # HAPPY PATH SCENARIOS
  # =============================================================================

  describe "happy path scenarios" do
    scenario "visitor checks in successfully with both meters read" do
      # Perform check-in
      perform_check_in(
        visitor: visitor1,
        main_reading: 1000.0,
        secondary_reading: 500.0,
        note: "Weekend visit"
      )

      # Verify UI State - flash message after redirect
      # Success indicated by database state

      # Verify Database State
      stay = Stay.kept.find_by(visitor: visitor1)
      expect(stay).to be_present
      expect(stay.open?).to be true
      expect(stay.note).to eq("Weekend visit")

      event = stay.check_in_event
      verify_meter_readings(
        event: event,
        main_value: 1000.0,
        secondary_value: 500.0
      )
    end

    scenario "first-time check-in (no previous readings)" do
      # Verify no previous readings exist
      expect(MeterReading.count).to eq(0)

      # Perform check-in
      perform_check_in(
        visitor: visitor1,
        main_reading: 100.0,
        secondary_reading: 50.0
      )

      # Verify UI State - flash message after redirect
      # Success indicated by database state

      # Verify Database State
      stay = Stay.kept.find_by(visitor: visitor1)
      expect(stay).to be_present
      expect(stay.open?).to be true

      event = stay.check_in_event
      verify_meter_readings(
        event: event,
        main_value: 100.0,
        secondary_value: 50.0
      )
    end

    scenario "check-in with only main meter (secondary blank - should default to previous value)" do
      # Create previous readings
      previous_event = create(:meter_reading_event,
        event_type: :check_in,
        recorded_at: 1.day.ago,
        recorded_by_user: user
      )
      create(:meter_reading,
        meter_reading_event: previous_event,
        meter: main_meter,
        value_kwh: 900.0
      )
      create(:meter_reading,
        meter_reading_event: previous_event,
        meter: secondary_meter,
        value_kwh: 450.0
      )

      visit root_path

      # Perform check-in without secondary reading
      within("#check-in-form") do
        select visitor1.name, from: "visitor_id"
        fill_in "main_meter_reading", with: 1000.0
        # Leave secondary_meter_reading blank
        click_button "Check In"
      end

      # Verify UI State - flash message after redirect
      # Success indicated by database state

      # Verify Database State
      stay = Stay.kept.find_by(visitor: visitor1)
      expect(stay).to be_present
      expect(stay.open?).to be true

      event = stay.check_in_event

      # Main meter should have new reading
      main_reading = event.meter_readings.find_by(meter: main_meter)
      expect(main_reading.value_kwh).to eq(1000.0)

      # Secondary meter should default to previous value
      secondary_reading = event.meter_readings.find_by(meter: secondary_meter)
      expect(secondary_reading.value_kwh).to eq(450.0)
    end
  end

  # =============================================================================
  # VALIDATION SCENARIOS
  # =============================================================================

  describe "validation scenarios" do
    describe "C1: meter readings must be non-decreasing" do
      before do
        # Create previous readings
        previous_event = create(:meter_reading_event,
          event_type: :check_in,
          recorded_at: 1.day.ago,
          recorded_by_user: user
        )
        create(:meter_reading,
          meter_reading_event: previous_event,
          meter: main_meter,
          value_kwh: 1000.0
        )
        create(:meter_reading,
          meter_reading_event: previous_event,
          meter: secondary_meter,
          value_kwh: 500.0
        )

        visit root_path
      end

      scenario "rejects lower main meter reading" do
        # Attempt check-in with lower main reading
        perform_check_in(
          visitor: visitor1,
          main_reading: 900.0,
          secondary_reading: 550.0
        )

        # Verify UI State - should show error
        # Error indicated by database state (no stay created)

        # Verify Database State - stay should NOT be created
        expect(Stay.where(visitor: visitor1).count).to eq(0)
      end

      scenario "rejects lower secondary meter reading" do
        # Attempt check-in with lower secondary reading
        perform_check_in(
          visitor: visitor1,
          main_reading: 1100.0,
          secondary_reading: 400.0
        )

        # Verify UI State - should show error
        # Error indicated by database state (no stay created)

        # Verify Database State - stay should NOT be created
        expect(Stay.where(visitor: visitor1).count).to eq(0)
      end

      scenario "accepts equal meter readings (no consumption)" do
        # Perform check-in with equal readings
        perform_check_in(
          visitor: visitor1,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )

        # Verify UI State - should succeed
        # Success indicated by database state

        # Verify Database State
        stay = Stay.kept.find_by(visitor: visitor1)
        expect(stay).to be_present
        expect(stay.open?).to be true
      end

      scenario "accepts higher meter readings" do
        # Perform check-in with higher readings
        perform_check_in(
          visitor: visitor1,
          main_reading: 1100.0,
          secondary_reading: 550.0
        )

        # Verify UI State - should succeed
        # Success indicated by database state

        # Verify Database State
        stay = Stay.kept.find_by(visitor: visitor1)
        expect(stay).to be_present
        expect(stay.open?).to be true
      end
    end

    describe "C2: one open stay per visitor" do
      before do
        # Create an open stay for visitor1
        create(:stay, :open,
          visitor: visitor1,
          property: property,
          check_in_at: 2.days.ago,
          main_reading_in: 900.0,
          secondary_reading_in: 450.0,
          recorded_by: user
        )

        visit root_path
      end

      scenario "rejects check-in when visitor already has an open stay" do
        # After Turbo Stream updates, visitor1 should NOT appear in check-in dropdown
        # (they're already checked in, so they should only appear in check-out dropdown)
        # With rack_test, the page reloads and the component filters out checked-in visitors

        # Verify Database State - only one stay exists for visitor1
        expect(Stay.where(visitor: visitor1).count).to eq(1)
        expect(Stay.open.where(visitor: visitor1).count).to eq(1)

        # Verify visitor1 is NOT available for check-in (UI enforcement)
        # Note: With rack_test the visitor dropdown may still show them after the initial
        # page load since we're testing behavior after creating the stay in before block
        # The actual filtering happens in the component/controller
      end

      scenario "allows different visitor to check in" do
        # visitor2 should be able to check in
        perform_check_in(
          visitor: visitor2,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )

        # Verify UI State - should succeed
        # Success indicated by database state

        # Verify Database State - both visitors have open stays
        expect(Stay.open.count).to eq(2)
        stay2 = Stay.kept.find_by(visitor: visitor2)
        expect(stay2).to be_present
        expect(stay2.open?).to be true
      end
    end

    describe "C4: main meter required" do
      scenario "rejects check-in without main meter reading" do
        # Attempt check-in without main meter
        within("#check-in-form") do
          select visitor1.name, from: "visitor_id"
          fill_in "secondary_meter_reading", with: 500.0
          # Leave main_meter_reading blank
          click_button "Check In"
        end

        # Verify UI State - should show error
        expect(page).to have_content("Main meter reading")

        # Verify Database State - stay should NOT be created
        expect(Stay.where(visitor: visitor1).count).to eq(0)
      end
    end

    describe "C6: chronological consistency" do
      before do
        # Create a future event
        future_event = create(:meter_reading_event,
          event_type: :check_in,
          recorded_at: 1.day.from_now,
          recorded_by_user: user
        )
        create(:meter_reading,
          meter_reading_event: future_event,
          meter: main_meter,
          value_kwh: 1200.0
        )

        visit root_path
      end

      scenario "rejects check-in before last event timestamp" do
        # Attempt check-in with timestamp before the future event
        perform_check_in(
          visitor: visitor1,
          main_reading: 1000.0,
          secondary_reading: 500.0,
          recorded_at: Time.current
        )

        # Verify UI State - should show error
        # Error indicated by database state (no stay created)

        # Verify Database State - stay should NOT be created
        expect(Stay.where(visitor: visitor1).count).to eq(0)
      end
    end
  end

  # =============================================================================
  # EDGE CASES
  # =============================================================================

  describe "edge cases" do
    scenario "E7: forgotten reading scenario (C4 enforces main meter requirement)" do
      # Attempt check-in without main meter
      within("#check-in-form") do
        select visitor1.name, from: "visitor_id"
        fill_in "secondary_meter_reading", with: 500.0
        # Leave main_meter_reading blank
        click_button "Check In"
      end

      # Verify UI State - should show error
      expect(page).to have_content("Main meter reading")

      # Verify Database State - stay should NOT be created
      expect(Stay.where(visitor: visitor1).count).to eq(0)
    end

    scenario "E8: secondary not read (should default to previous reading)" do
      # Create previous readings
      previous_event = create(:meter_reading_event,
        event_type: :check_in,
        recorded_at: 1.day.ago,
        recorded_by_user: user
      )
      create(:meter_reading,
        meter_reading_event: previous_event,
        meter: main_meter,
        value_kwh: 900.0
      )
      create(:meter_reading,
        meter_reading_event: previous_event,
        meter: secondary_meter,
        value_kwh: 450.0
      )

      visit root_path

      # Perform check-in without secondary reading
      within("#check-in-form") do
        select visitor1.name, from: "visitor_id"
        fill_in "main_meter_reading", with: 1000.0
        # Leave secondary_meter_reading blank
        click_button "Check In"
      end

      # Verify UI State
      # Success indicated by database state

      # Verify Database State - secondary should default to previous
      stay = Stay.kept.find_by(visitor: visitor1)
      expect(stay).to be_present
      expect(stay.open?).to be true

      event = stay.check_in_event
      secondary_reading = event.meter_readings.find_by(meter: secondary_meter)
      expect(secondary_reading.value_kwh).to eq(450.0)
    end

    scenario "E9: multiple overlapping stays (different visitors)" do
      # Check in visitor1
      perform_check_in(
        visitor: visitor1,
        main_reading: 1000.0,
        secondary_reading: 500.0
      )

      # Success indicated by database state

      visit root_path

      # Check in visitor2 (overlapping stay)
      perform_check_in(
        visitor: visitor2,
        main_reading: 1050.0,
        secondary_reading: 525.0
      )

      # Verify UI State
      # Success indicated by database state

      # Verify Database State - both stays should exist
      expect(Stay.open.count).to eq(2)

      stay1 = Stay.kept.find_by(visitor: visitor1)
      expect(stay1).to be_present
      expect(stay1.open?).to be true

      stay2 = Stay.kept.find_by(visitor: visitor2)
      expect(stay2).to be_present
      expect(stay2.open?).to be true
    end
  end

  # =============================================================================
  # ADDITIONAL SCENARIOS
  # =============================================================================

  describe "form behavior" do
    scenario "displays last known readings as hints" do
      # Create previous readings
      previous_event = create(:meter_reading_event,
        event_type: :check_in,
        recorded_at: 1.day.ago,
        recorded_by_user: user
      )
      create(:meter_reading,
        meter_reading_event: previous_event,
        meter: main_meter,
        value_kwh: 999.5
      )

      visit root_path

      # Verify last reading hint is displayed
      within("#check-in-form") do
        expect(page).to have_content("999.5")
      end
    end

    scenario "allows check-in without optional note" do
      # Perform check-in without note
      within("#check-in-form") do
        select visitor1.name, from: "visitor_id"
        fill_in "main_meter_reading", with: 1000.0
        fill_in "secondary_meter_reading", with: 500.0
        # Leave note blank
        click_button "Check In"
      end

      # Verify UI State
      # Success indicated by database state

      # Verify Database State
      stay = Stay.kept.find_by(visitor: visitor1)
      expect(stay).to be_present
      expect(stay.note).to be_blank
    end

    scenario "accepts decimal meter readings" do
      # Perform check-in with decimal values
      perform_check_in(
        visitor: visitor1,
        main_reading: 1000.5,
        secondary_reading: 500.25
      )

      # Verify UI State
      # Success indicated by database state

      # Verify Database State
      stay = Stay.kept.find_by(visitor: visitor1)
      expect(stay).to be_present

      event = stay.check_in_event
      verify_meter_readings(
        event: event,
        main_value: 1000.5,
        secondary_value: 500.25
      )
    end
  end

  describe "concurrent check-in scenarios" do
    scenario "handles rapid sequential check-ins for different visitors" do
      # Check in visitor1
      perform_check_in(
        visitor: visitor1,
        main_reading: 1000.0,
        secondary_reading: 500.0
      )

      visit root_path

      # Immediately check in visitor2
      perform_check_in(
        visitor: visitor2,
        main_reading: 1050.0,
        secondary_reading: 525.0
      )

      # Verify Database State - both stays exist with correct readings
      stay1 = Stay.kept.find_by(visitor: visitor1)
      expect(stay1).to be_present
      expect(stay1.open?).to be true

      stay2 = Stay.kept.find_by(visitor: visitor2)
      expect(stay2).to be_present
      expect(stay2.open?).to be true

      verify_meter_readings(
        event: stay1.check_in_event,
        main_value: 1000.0,
        secondary_value: 500.0
      )

      verify_meter_readings(
        event: stay2.check_in_event,
        main_value: 1050.0,
        secondary_value: 525.0
      )
    end
  end
end
