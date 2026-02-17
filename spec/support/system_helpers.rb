# frozen_string_literal: true

# System test helper methods for end-to-end testing
#
# Provides utilities for:
# - Waiting for Turbo Stream updates
# - Filling in forms (meter readings, visitor selection)
# - Verifying flash messages
# - Checking database state alongside UI state
# - Building complex test scenarios
module SystemHelpers
  # Wait for Turbo to finish rendering
  # Useful after form submissions that trigger Turbo Stream responses
  def wait_for_turbo
    # Capybara's implicit waiting should handle most cases
    # but we can add explicit wait if needed
    expect(page).to have_no_css('.turbo-progress-bar', wait: 5)
  rescue Capybara::ElementNotFound
    # Progress bar might not appear for fast responses - that's fine
  end

  # Perform a visitor check-in through the UI
  #
  # @param visitor [Visitor] The visitor to check in
  # @param main_reading [Float] Main meter reading in kWh
  # @param secondary_reading [Float, nil] Secondary meter reading in kWh (optional)
  # @param note [String, nil] Optional note
  # @param recorded_at [Time, nil] Optional timestamp (defaults to current time)
  def perform_check_in(visitor:, main_reading:, secondary_reading: nil, note: nil, recorded_at: nil)
    within("#check-in-form") do
      select visitor.name, from: "visitor_id"
      fill_in "recorded_at", with: (recorded_at || Time.current).strftime("%Y-%m-%dT%H:%M")
      fill_in "main_meter_reading", with: main_reading

      if secondary_reading.present?
        fill_in "secondary_meter_reading", with: secondary_reading
      end

      fill_in "note", with: note if note.present?

      click_button "Check In"
    end

    wait_for_turbo
  end

  # Perform a visitor check-out through the UI
  #
  # @param visitor [Visitor] The visitor to check out
  # @param main_reading [Float] Main meter reading in kWh
  # @param secondary_reading [Float, nil] Secondary meter reading in kWh (optional)
  # @param note [String, nil] Optional note
  # @param recorded_at [Time, nil] Optional timestamp (defaults to current time)
  def perform_check_out(visitor:, main_reading:, secondary_reading: nil, note: nil, recorded_at: nil)
    within("#check-out-form") do
      select visitor.name, from: "visitor_id"
      fill_in "recorded_at", with: (recorded_at || Time.current).strftime("%Y-%m-%dT%H:%M")
      fill_in "main_meter_reading", with: main_reading

      if secondary_reading.present?
        fill_in "secondary_meter_reading", with: secondary_reading
      end

      fill_in "note", with: note if note.present?

      click_button "Check Out"
    end

    wait_for_turbo
  end

  # Create a manual consumption entry through the UI
  #
  # @param amount_kwh [Float] Consumption amount in kWh
  # @param date [Date, String] Date for the entry
  # @param description [String, nil] Optional description
  def create_manual_entry(amount_kwh:, date:, description: nil)
    within("#manual-entry-form") do
      fill_in "amount_kwh", with: amount_kwh
      fill_in "date", with: date.is_a?(Date) ? date.strftime("%Y-%m-%d") : date
      fill_in "description", with: description if description.present?

      click_button "Add Entry"
    end

    wait_for_turbo
  end

  # Verify that a flash message is displayed
  #
  # @param type [:notice, :alert] Type of flash message
  # @param text [String] Expected text (partial match)
  def expect_flash(type, text)
    case type
    when :notice
      expect(page).to have_css('.flash-notice, .alert-success, .bg-green-50', text: text)
    when :alert
      expect(page).to have_css('.flash-alert, .alert-error, .bg-red-50', text: text)
    when :warning
      expect(page).to have_css('.flash-warning, .alert-warning, .bg-yellow-50', text: text)
    end
  end

  # Verify a visitor is in the current visitors list
  #
  # @param visitor [Visitor] The visitor to check for
  def expect_visitor_present(visitor)
    within("#current-visitors") do
      expect(page).to have_content(visitor.name)
    end
  end

  # Verify a visitor is NOT in the current visitors list
  #
  # @param visitor [Visitor] The visitor to check for
  def expect_visitor_absent(visitor)
    within("#current-visitors") do
      expect(page).to have_no_content(visitor.name)
    end
  end

  # Build a timeline with multiple stays for testing complex scenarios
  #
  # @example
  #   timeline = build_timeline(property) do |t|
  #     t.add_stay(alice, check_in: 3.days.ago, check_out: 1.day.ago)
  #     t.add_stay(bob, check_in: 2.days.ago) # Still open
  #     t.add_manual_entry(5.0, date: 4.days.ago)
  #   end
  #
  # @param property [Property] The property to build timeline for
  # @yield [TimelineBuilder] Builder object for adding stays and entries
  # @return [TimelineBuilder] The builder with all created records
  def build_timeline(property)
    builder = TimelineBuilder.new(property)
    yield builder if block_given?
    builder
  end

  # Helper class for building complex test timelines
  class TimelineBuilder
    attr_reader :property, :stays, :manual_entries, :user

    def initialize(property)
      @property = property
      @stays = []
      @manual_entries = []
      @user = FactoryBot.create(:user)
    end

    # Add a stay to the timeline
    #
    # @param visitor [Visitor] The visitor
    # @param check_in [Time, Date] Check-in timestamp
    # @param check_out [Time, Date, nil] Check-out timestamp (nil for open stay)
    # @param main_reading_in [Float] Main meter reading at check-in
    # @param secondary_reading_in [Float] Secondary meter reading at check-in
    # @param main_reading_out [Float, nil] Main meter reading at check-out
    # @param secondary_reading_out [Float, nil] Secondary meter reading at check-out
    # @return [Stay] The created stay
    def add_stay(visitor, check_in:, check_out: nil,
                 main_reading_in: 1000.0, secondary_reading_in: 500.0,
                 main_reading_out: nil, secondary_reading_out: nil)
      if check_out.present?
        # Closed stay
        main_reading_out ||= main_reading_in + 50.0
        secondary_reading_out ||= secondary_reading_in + 25.0

        stay = FactoryBot.create(:stay, :closed,
          visitor: visitor,
          property: property,
          check_in_at: check_in,
          check_out_at: check_out,
          main_reading_in: main_reading_in,
          secondary_reading_in: secondary_reading_in,
          main_reading_out: main_reading_out,
          secondary_reading_out: secondary_reading_out,
          recorded_by: user
        )
      else
        # Open stay
        stay = FactoryBot.create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: check_in,
          main_reading_in: main_reading_in,
          secondary_reading_in: secondary_reading_in,
          recorded_by: user
        )
      end

      @stays << stay
      stay
    end

    # Add a manual consumption entry to the timeline
    #
    # @param amount_kwh [Float] Consumption amount in kWh
    # @param date [Date, Time] Date of consumption
    # @param description [String, nil] Optional description
    # @return [ManualConsumptionEntry] The created entry
    def add_manual_entry(amount_kwh, date:, description: nil)
      entry = FactoryBot.create(:manual_consumption_entry,
        property: property,
        amount_kwh: amount_kwh,
        consumption_date: date.to_date,
        description: description,
        recorded_by_user: user
      )

      @manual_entries << entry
      entry
    end
  end

  # Verify database state for a stay
  #
  # @param visitor [Visitor] The visitor
  # @param status [String] Expected stay status ('open' or 'closed')
  # @return [Stay, nil] The found stay or nil
  def verify_stay_exists(visitor:, status: 'open')
    stay = Stay.kept.find_by(visitor: visitor, status: status)
    expect(stay).to be_present, "Expected #{status} stay for #{visitor.name} but found none"
    stay
  end

  # Verify meter readings were created for an event
  #
  # @param event [MeterReadingEvent] The event
  # @param main_value [Float] Expected main meter reading
  # @param secondary_value [Float, nil] Expected secondary meter reading (nil to skip check)
  def verify_meter_readings(event:, main_value:, secondary_value: nil)
    expect(event).to be_present

    main_meter = event.property.meters.find_by(meter_type: 'main')
    main_reading = event.meter_readings.find_by(meter: main_meter)
    expect(main_reading.value_kwh).to eq(main_value),
      "Expected main meter reading #{main_value} but got #{main_reading.value_kwh}"

    if secondary_value.present?
      secondary_meter = event.property.meters.find_by(meter_type: 'secondary')
      secondary_reading = event.meter_readings.find_by(meter: secondary_meter)
      expect(secondary_reading.value_kwh).to eq(secondary_value),
        "Expected secondary meter reading #{secondary_value} but got #{secondary_reading.value_kwh}"
    end
  end

  # Visit the consumption report page for a date range
  #
  # @param from [Date] Start date
  # @param to [Date] End date
  def visit_consumption_report(from:, to:)
    visit consumption_reports_path(from: from.strftime("%Y-%m-%d"), to: to.strftime("%Y-%m-%d"))
  end

  # Visit the readings history page
  def visit_readings_history
    visit readings_history_index_path
  end
end
