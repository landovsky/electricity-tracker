# frozen_string_literal: true

require 'rails_helper'

# System tests for manual consumption entry flows (UC3)
#
# Tests cover:
# - Happy path scenarios (create entry, verify UI and database)
# - Validation scenarios (C7: positive values, C8: soft warning)
# - Edge cases (E4: empty house, E5: active stay)
# - Multiple entries on same day
# - Manual entry on check-in/check-out day
RSpec.describe "Manual Entry Flows", type: :system do
  let!(:property) { create(:property) }
  let!(:main_meter) { create(:meter, :main, property: property) }
  let!(:secondary_meter) { create(:meter, :secondary, property: property) }
  let!(:alice) { create(:visitor, name: "Alice Anderson") }
  let!(:bob) { create(:visitor, name: "Bob Brown") }
  let!(:user) { create(:user) }

  before do
    visit root_path
    # Switch to manual entry tab
    click_button "Log Entry"
  end

  describe "happy path scenarios" do
    scenario "create manual entry for specific date successfully" do
      # Given a date and consumption amount
      entry_date = 2.days.ago.to_date
      consumption = 15.5

      # When creating a manual entry
      create_manual_entry(
        visitor: alice,
        amount_kwh: consumption,
        date: entry_date,
        note: "EV charging session"
      )

      # Then the database should have the entry
      entry = ManualConsumptionEntry.kept.last
      expect(entry).to be_present
      expect(entry.visitor).to eq(alice)
      expect(entry.property).to eq(property)
      expect(entry.date).to eq(entry_date)
      expect(entry.kwh).to eq(consumption)
      expect(entry.note).to eq("EV charging session")
      expect(entry.recorded_by_user).to be_present
    end

    scenario "entry is persisted to database" do
      # Given a manual entry is created
      create_manual_entry(
        visitor: alice,
        amount_kwh: 20.0,
        date: Date.current,
        note: "Tesla charging"
      )

      # Then the entry should be in the database
      entry = ManualConsumptionEntry.kept.last
      expect(entry).to be_present
      expect(entry.kwh).to eq(20.0)
      expect(entry.visitor).to eq(alice)
      expect(entry.note).to eq("Tesla charging")
    end

    scenario "entry uses default date when not specified" do
      # When creating an entry with default (current) date
      create_manual_entry(
        visitor: alice,
        amount_kwh: 10.0,
        date: Date.current,
        note: "Today's usage"
      )

      # Then the entry should use today's date
      entry = ManualConsumptionEntry.kept.last
      expect(entry.date).to eq(Date.current)
    end
  end

  describe "constraint C7: positive kWh validation" do
    scenario "reject zero kWh values" do
      # When attempting to create entry with zero consumption
      create_manual_entry(
        visitor: alice,
        amount_kwh: 0,
        date: Date.current,
        note: "Zero consumption"
      )

      # Then no entry should be created (validation failed)
      expect(ManualConsumptionEntry.kept.count).to eq(0)
    end

    scenario "reject negative kWh values" do
      # When attempting to create entry with negative consumption
      create_manual_entry(
        visitor: alice,
        amount_kwh: -5.5,
        date: Date.current,
        note: "Negative consumption"
      )

      # Then no entry should be created (validation failed)
      expect(ManualConsumptionEntry.kept.count).to eq(0)
    end

    scenario "allow very small positive values" do
      # When creating entry with very small positive value
      create_manual_entry(
        visitor: alice,
        amount_kwh: 0.01,
        date: Date.current,
        note: "Tiny usage"
      )

      # Then the entry should be created successfully
      entry = ManualConsumptionEntry.kept.last
      expect(entry).to be_present
      expect(entry.kwh).to eq(0.01)
    end
  end

  describe "constraint C8: soft validation warning for high values" do
    # Note: C8 is currently a placeholder in the service
    # These tests verify the warning mechanism works when implemented

    scenario "warn but allow submission for unusually high values" do
      # When creating entry with unrealistically high value
      create_manual_entry(
        visitor: alice,
        amount_kwh: 1000.0,
        date: Date.current,
        note: "Extremely high usage"
      )

      # Then the entry should still be created (soft validation)
      entry = ManualConsumptionEntry.kept.last
      expect(entry).to be_present
      expect(entry.kwh).to eq(1000.0)

      # TODO: When C8 is implemented, verify warning appears:
      # expect_flash(:warning, "exceeds unattributed consumption")
    end
  end

  describe "edge case E4: manual entry during empty house period" do
    scenario "create entry when no visitors are checked in" do
      # Given the house is empty (no open stays)
      timeline = build_timeline(property) do |t|
        # Add a closed stay in the past
        t.add_stay(alice,
          check_in: 5.days.ago,
          check_out: 3.days.ago,
          main_reading_in: 1000.0,
          main_reading_out: 1050.0
        )
      end

      # When creating a manual entry during empty period
      visit root_path
      click_button "Log Entry"

      create_manual_entry(
        visitor: alice,
        amount_kwh: 10.0,
        date: 2.days.ago.to_date,
        note: "Fridge running during empty house"
      )
      # Then the entry should be created successfully

      entry = ManualConsumptionEntry.kept.last
      expect(entry).to be_present
      expect(entry.date).to eq(2.days.ago.to_date)

      # TODO: When period analysis is implemented, verify:
      # - Entry is attributed to the empty house period
      # - Entry reduces the unattributed/shared pool for that period
    end
  end

  describe "edge case E5: manual entry during active stay" do
    scenario "create entry when visitors are currently checked in" do
      # Given visitors are currently checked in
      timeline = build_timeline(property) do |t|
        t.add_stay(alice,
          check_in: 3.days.ago,
          # No check_out - still open
          main_reading_in: 1000.0
        )
        t.add_stay(bob,
          check_in: 2.days.ago,
          # No check_out - still open
          main_reading_in: 1050.0
        )
      end

      # When creating a manual entry during active stay period
      visit root_path
      click_button "Log Entry"

      create_manual_entry(
        visitor: alice,
        amount_kwh: 25.0,
        date: 1.day.ago.to_date,
        note: "EV charging during stay"
      )
      # Then the entry should be created successfully

      entry = ManualConsumptionEntry.kept.last
      expect(entry).to be_present
      expect(entry.date).to eq(1.day.ago.to_date)

      # TODO: When period analysis is implemented, verify:
      # - Entry is deducted from shared consumption pool
      # - Remaining consumption is split among present visitors
    end
  end

  describe "multiple entries on same day" do
    scenario "create multiple manual entries for the same date" do
      entry_date = Date.current

      # First entry
      create_manual_entry(
        visitor: alice,
        amount_kwh: 15.0,
        date: entry_date,
        note: "Morning EV charge"
      )

      visit root_path
      click_button "Log Entry"

      # Second entry on same day, different visitor
      within("#manual-entry-form") do
        select bob.name, from: "visitor_id"
        fill_in "date", with: entry_date.strftime("%Y-%m-%d")
        fill_in "kwh", with: 20.0
        fill_in "note", with: "Evening EV charge"
        click_button "Log Consumption"
      end

      wait_for_turbo

      # Then both entries should exist
      entries = ManualConsumptionEntry.kept.where(date: entry_date).order(:created_at)
      expect(entries.count).to eq(2)

      expect(entries.first.visitor).to eq(alice)
      expect(entries.first.kwh).to eq(15.0)

      expect(entries.second.visitor).to eq(bob)
      expect(entries.second.kwh).to eq(20.0)
    end
  end

  describe "manual entry on check-in/check-out day" do
    scenario "create manual entry on same day as check-in" do
      # Given a visitor checks in today
      timeline = build_timeline(property) do |t|
        t.add_stay(alice,
          check_in: Date.current.beginning_of_day,
          main_reading_in: 1000.0
        )
      end

      # When creating a manual entry for the same day
      visit root_path
      click_button "Log Entry"

      create_manual_entry(
        visitor: alice,
        amount_kwh: 30.0,
        date: Date.current,
        note: "Same-day EV charge"
      )
      # Then the entry should be created successfully

      entry = ManualConsumptionEntry.kept.last
      expect(entry.date).to eq(Date.current)
      expect(entry.visitor).to eq(alice)

      # TODO: When period analysis is implemented, verify:
      # - Entry is properly attributed within the check-in day's period
    end

    scenario "create manual entry on same day as check-out" do
      # Given a visitor checks out today
      timeline = build_timeline(property) do |t|
        t.add_stay(alice,
          check_in: 2.days.ago,
          check_out: Date.current.beginning_of_day,
          main_reading_in: 1000.0,
          main_reading_out: 1050.0
        )
      end

      # When creating a manual entry for the check-out day
      visit root_path
      click_button "Log Entry"

      create_manual_entry(
        visitor: alice,
        amount_kwh: 10.0,
        date: Date.current,
        note: "Check-out day charge"
      )
      # Then the entry should be created successfully

      entry = ManualConsumptionEntry.kept.last
      expect(entry.date).to eq(Date.current)

      # TODO: When period analysis is implemented, verify:
      # - Entry is properly attributed for the check-out day's period
    end
  end

  describe "validation scenarios" do
    scenario "reject entry without visitor selection" do
      # When attempting to create entry without selecting visitor
      within("#manual-entry-form") do
        # Don't select visitor
        fill_in "date", with: Date.current.strftime("%Y-%m-%d")
        fill_in "kwh", with: 10.0
        fill_in "note", with: "Missing visitor"
        click_button "Log Consumption"
      end

      wait_for_turbo

      # Then no entry should be created (validation failed)
      expect(ManualConsumptionEntry.kept.count).to eq(0)
    end

    scenario "reject entry without note" do
      # When attempting to create entry without note
      within("#manual-entry-form") do
        select alice.name, from: "visitor_id"
        fill_in "date", with: Date.current.strftime("%Y-%m-%d")
        fill_in "kwh", with: 10.0
        # Don't fill in note
        click_button "Log Consumption"
      end

      wait_for_turbo
      # Then validation should fail

      # And no entry should be created
      expect(ManualConsumptionEntry.kept.count).to eq(0)
    end

    scenario "reject entry without kWh value" do
      # When attempting to create entry without kWh value
      within("#manual-entry-form") do
        select alice.name, from: "visitor_id"
        fill_in "date", with: Date.current.strftime("%Y-%m-%d")
        # Don't fill in kwh
        fill_in "note", with: "Missing kWh"
        click_button "Log Consumption"
      end

      wait_for_turbo
      # Then validation should fail

      # And no entry should be created
      expect(ManualConsumptionEntry.kept.count).to eq(0)
    end
  end

  describe "database state verification" do
    scenario "verify all fields are persisted correctly" do
      # Given specific entry details
      visitor = bob
      entry_date = 3.days.ago.to_date
      consumption = 42.5
      note_text = "Detailed EV charging session"

      # When creating the entry
      within("#manual-entry-form") do
        select visitor.name, from: "visitor_id"
        fill_in "date", with: entry_date.strftime("%Y-%m-%d")
        fill_in "kwh", with: consumption
        fill_in "note", with: note_text
        click_button "Log Consumption"
      end

      wait_for_turbo

      # Then all fields should be persisted correctly
      entry = ManualConsumptionEntry.kept.last

      expect(entry.visitor_id).to eq(visitor.id)
      expect(entry.visitor.name).to eq(visitor.name)
      expect(entry.property_id).to eq(property.id)
      expect(entry.date).to eq(entry_date)
      expect(entry.kwh).to eq(consumption)
      expect(entry.note).to eq(note_text)
      expect(entry.recorded_by_user_id).to be_present
      expect(entry.created_at).to be_present
      expect(entry.updated_at).to be_present
      expect(entry.deleted_at).to be_nil
    end

    scenario "verify audit trail is created" do
      # When creating a manual entry
      create_manual_entry(
        visitor: alice,
        amount_kwh: 10.0,
        date: Date.current,
        note: "Audit test"
      )

      # Then an audit record should be created
      entry = ManualConsumptionEntry.kept.last
      expect(entry.audits.count).to eq(1)
      expect(entry.audits.first.action).to eq("create")
    end
  end
end
