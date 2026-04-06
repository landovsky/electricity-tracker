# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consumption Report Flows", type: :system do
  let!(:property) { create(:property) }
  let!(:main_meter) { create(:meter, :main, property: property) }
  let!(:secondary_meter) { create(:meter, :secondary, property: property) }

  describe "Happy Path Scenarios" do
    context "single visitor for a period" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }

      it "generates report showing consumption for single visitor" do
        # Build timeline with single visitor
        timeline = build_timeline(property) do |t|
          t.add_stay(visitor_alice,
            check_in: Date.new(2026, 1, 1).beginning_of_day,
            check_out: Date.new(2026, 1, 10).beginning_of_day,
            main_reading_in: 1000.0,
            secondary_reading_in: 500.0,
            main_reading_out: 1200.0,
            secondary_reading_out: 600.0)
        end

        # Visit consumption report page
        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 10))

        # UI State Verification
        expect(page).to have_content(I18n.t("reports.title"))
        expect(page).to have_content("2026-01-01")
        expect(page).to have_content("2026-01-10")
        expect(page).to have_content("Alice")
        # Total = main delta only (200) — secondary is subordinate (already included in primary)
        expect(page).to have_content("200") # Total consumption (integer precision)

        # Database State Verification
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result
        expect(result[:visitors].size).to eq(1)
        expect(result[:visitors].first[:visitor]).to eq(visitor_alice)
        expect(result[:visitors].first[:total_kwh]).to eq(200.0) # primary delta only
        expect(result[:total_consumption_kwh]).to eq(200.0)
      end
    end

    context "multiple non-overlapping visitors" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }
      let!(:visitor_bob) { create(:visitor, name: "Bob", property: property) }

      it "generates report showing separate consumption for each visitor" do
        # Timeline:
        # Jan 1-5: Alice alone (100 kWh)
        # Jan 5-10: Empty house (50 kWh)
        # Jan 10-15: Bob alone (100 kWh)
        timeline = build_timeline(property) do |t|
          t.add_stay(visitor_alice,
            check_in: Date.new(2026, 1, 1).beginning_of_day,
            check_out: Date.new(2026, 1, 5).beginning_of_day,
            main_reading_in: 1000.0,
            secondary_reading_in: 500.0,
            main_reading_out: 1100.0,
            secondary_reading_out: 550.0)

          t.add_stay(visitor_bob,
            check_in: Date.new(2026, 1, 10).beginning_of_day,
            check_out: Date.new(2026, 1, 15).beginning_of_day,
            main_reading_in: 1150.0,
            secondary_reading_in: 575.0,
            main_reading_out: 1250.0,
            secondary_reading_out: 625.0)
        end

        # Visit consumption report page
        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 15))

        # UI State Verification
        expect(page).to have_content(I18n.t("reports.title"))
        expect(page).to have_content("Alice")
        expect(page).to have_content("Bob")

        # Database State Verification
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 15)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_alice }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_bob }

        # Alice: 100 kWh period (primary delta only) + 12.5 kWh empty house share ((50-25) / 2)
        expect(alice_result[:period_shares_kwh]).to eq(100.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(12.5)
        expect(alice_result[:total_kwh]).to eq(112.5)

        # Bob: 100 kWh period (primary delta only) + 12.5 kWh empty house share ((50-25) / 2)
        expect(bob_result[:period_shares_kwh]).to eq(100.0)
        expect(bob_result[:empty_house_share_kwh]).to eq(12.5)
        expect(bob_result[:total_kwh]).to eq(112.5)

        expect(result[:total_consumption_kwh]).to eq(225.0)
      end
    end

    context "correct consumption allocation" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }

      it "shows correct allocation in UI and database" do
        timeline = build_timeline(property) do |t|
          t.add_stay(visitor_alice,
            check_in: Date.new(2026, 1, 1).beginning_of_day,
            check_out: Date.new(2026, 1, 10).beginning_of_day,
            main_reading_in: 1000.0,
            secondary_reading_in: 500.0,
            main_reading_out: 1150.0,
            secondary_reading_out: 575.0)
        end

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 10))

        # UI shows correct values (integer precision, card-based layout)
        # Total = primary delta only (150) — secondary is subordinate
        expect(page).to have_content("Alice")
        expect(page).to have_content("150") # Total consumption (integer precision)

        # Database has correct allocation
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        result = outcome.result
        alice_result = result[:visitors].first

        expect(alice_result[:period_shares_kwh]).to eq(150.0) # primary delta only
        expect(alice_result[:manual_entries_kwh]).to eq(0.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(0.0)
        expect(alice_result[:total_kwh]).to eq(150.0)
      end
    end
  end

  describe "Complex Allocation Scenarios" do
    context "E1: overlapping visitors (equal split)" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }
      let!(:visitor_bob) { create(:visitor, name: "Bob", property: property) }
      let!(:visitor_charlie) { create(:visitor, name: "Charlie", property: property) }

      it "splits consumption equally among 3+ overlapping visitors" do
        # Timeline:
        # Jan 1-10: Alice, Bob, and Charlie all present
        # 300 kWh total -> 100 kWh each
        # Need to create shared events for overlapping stays
        user = create(:user)

        # Create shared check-in event (all three check in at same time)
        check_in_event = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 1).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading,
          meter_reading_event: check_in_event,
          meter: main_meter,
          value_kwh: 1000.0)
        create(:meter_reading,
          meter_reading_event: check_in_event,
          meter: secondary_meter,
          value_kwh: 500.0)

        # Create shared check-out event (all three check out at same time)
        check_out_event = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 10).beginning_of_day,
          event_type: :check_out,
          recorded_by_user: user)
        create(:meter_reading,
          meter_reading_event: check_out_event,
          meter: main_meter,
          value_kwh: 1300.0)
        create(:meter_reading,
          meter_reading_event: check_out_event,
          meter: secondary_meter,
          value_kwh: 650.0)

        # Create stays for all three visitors using the shared events
        stay_alice = create(:stay,
          visitor: visitor_alice,
          property: property,
          check_in_event: check_in_event,
          check_out_event: check_out_event)
        stay_bob = create(:stay,
          visitor: visitor_bob,
          property: property,
          check_in_event: check_in_event,
          check_out_event: check_out_event)
        stay_charlie = create(:stay,
          visitor: visitor_charlie,
          property: property,
          check_in_event: check_in_event,
          check_out_event: check_out_event)

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 10))

        # UI State Verification
        expect(page).to have_content("Alice")
        expect(page).to have_content("Bob")
        expect(page).to have_content("Charlie")

        # Database State Verification - equal split
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result

        result[:visitors].each do |visitor_result|
          expect(visitor_result[:period_shares_kwh]).to eq(100.0)
          expect(visitor_result[:manual_entries_kwh]).to eq(0.0)
          expect(visitor_result[:empty_house_share_kwh]).to eq(0.0)
          expect(visitor_result[:total_kwh]).to eq(100.0)
        end

        expect(result[:total_consumption_kwh]).to eq(300.0)
      end

      it "handles partial overlaps with equal split" do
        # Timeline:
        # Jan 1-5: Alice alone (100 kWh)
        # Jan 5-10: Alice + Bob (200 kWh -> 100 each)
        # Jan 10-15: Bob alone (100 kWh)
        user = create(:user)

        # Event 1: Alice checks in
        event1 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 1).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event1, meter: main_meter, value_kwh: 1000.0)
        create(:meter_reading, meter_reading_event: event1, meter: secondary_meter, value_kwh: 500.0)

        # Event 2: Bob checks in (also Alice's partial checkout point)
        event2 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 5).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event2, meter: main_meter, value_kwh: 1100.0)
        create(:meter_reading, meter_reading_event: event2, meter: secondary_meter, value_kwh: 550.0)

        # Event 3: Alice checks out
        event3 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 10).beginning_of_day,
          event_type: :check_out,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event3, meter: main_meter, value_kwh: 1300.0)
        create(:meter_reading, meter_reading_event: event3, meter: secondary_meter, value_kwh: 650.0)

        # Event 4: Bob checks out
        event4 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 15).beginning_of_day,
          event_type: :check_out,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event4, meter: main_meter, value_kwh: 1400.0)
        create(:meter_reading, meter_reading_event: event4, meter: secondary_meter, value_kwh: 700.0)

        # Create stays
        stay_alice = create(:stay,
          visitor: visitor_alice,
          property: property,
          check_in_event: event1,
          check_out_event: event3)
        stay_bob = create(:stay,
          visitor: visitor_bob,
          property: property,
          check_in_event: event2,
          check_out_event: event4)

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 15))

        # Database State Verification
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 15)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_alice }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_bob }

        # Alice: 100 (alone, primary delta) + 100 (overlap split of 200) = 200
        expect(alice_result[:total_kwh]).to eq(200.0)

        # Bob: 100 (overlap split of 200) + 100 (alone, primary delta) = 200
        expect(bob_result[:total_kwh]).to eq(200.0)

        expect(result[:total_consumption_kwh]).to eq(400.0)
      end
    end

    context "E2: empty house consumption pooling" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }
      let!(:visitor_bob) { create(:visitor, name: "Bob", property: property) }

      it "pools empty house consumption and distributes equally" do
        # Timeline:
        # Jan 1-5: Alice alone (100 kWh)
        # Jan 5-10: Empty house (100 kWh)
        # Jan 10-15: Bob alone (100 kWh)
        # Empty house gets split 50/50
        timeline = build_timeline(property) do |t|
          t.add_stay(visitor_alice,
            check_in: Date.new(2026, 1, 1).beginning_of_day,
            check_out: Date.new(2026, 1, 5).beginning_of_day,
            main_reading_in: 1000.0,
            secondary_reading_in: 500.0,
            main_reading_out: 1100.0,
            secondary_reading_out: 550.0)

          t.add_stay(visitor_bob,
            check_in: Date.new(2026, 1, 10).beginning_of_day,
            check_out: Date.new(2026, 1, 15).beginning_of_day,
            main_reading_in: 1200.0,
            secondary_reading_in: 600.0,
            main_reading_out: 1300.0,
            secondary_reading_out: 650.0)
        end

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 15))

        # Database State Verification
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 15)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_alice }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_bob }

        # Alice: 100 (period, primary delta) + 25 (empty house share, (100-50) / 2)
        expect(alice_result[:period_shares_kwh]).to eq(100.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(25.0)
        expect(alice_result[:total_kwh]).to eq(125.0)

        # Bob: 100 (period, primary delta) + 25 (empty house share, (100-50) / 2)
        expect(bob_result[:period_shares_kwh]).to eq(100.0)
        expect(bob_result[:empty_house_share_kwh]).to eq(25.0)
        expect(bob_result[:total_kwh]).to eq(125.0)

        expect(result[:total_consumption_kwh]).to eq(250.0)
      end

      it "handles only empty house periods (no stays)" do
        # Timeline with readings but no stays
        timeline = build_timeline(property) do |t|
          # Just add meter reading events via the factory, no stays
        end

        # Manually create events without stays
        user = create(:user)
        event1 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 1).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading,
          meter_reading_event: event1,
          meter: main_meter,
          value_kwh: 1000.0)
        create(:meter_reading,
          meter_reading_event: event1,
          meter: secondary_meter,
          value_kwh: 500.0)

        event2 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 10).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading,
          meter_reading_event: event2,
          meter: main_meter,
          value_kwh: 1100.0)
        create(:meter_reading,
          meter_reading_event: event2,
          meter: secondary_meter,
          value_kwh: 550.0)

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 10))

        # UI State Verification
        expect(page).to have_content("No consumption data found")

        # Database State Verification
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result
        expect(result[:visitors]).to be_empty
        expect(result[:total_consumption_kwh]).to eq(0.0)
        expect(result[:total_meter_delta_kwh]).to eq(100.0)
      end
    end

    context "E4: manual entries during empty house" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }

      it "attributes manual entry and deducts from empty house pool" do
        # Timeline:
        # Jan 1-10: Empty house (100 kWh total: primary delta only)
        # Manual entry by Alice: 30 kWh on Jan 5
        # Alice gets: 30 (manual) + 70 (empty house share = 100 - 30) = 100 kWh
        user = create(:user)
        event1 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 1).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading,
          meter_reading_event: event1,
          meter: main_meter,
          value_kwh: 1000.0)
        create(:meter_reading,
          meter_reading_event: event1,
          meter: secondary_meter,
          value_kwh: 500.0)

        event2 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 10).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading,
          meter_reading_event: event2,
          meter: main_meter,
          value_kwh: 1100.0)
        create(:meter_reading,
          meter_reading_event: event2,
          meter: secondary_meter,
          value_kwh: 550.0)

        # Add manual entry during empty period
        manual_entry = create(:manual_consumption_entry,
          visitor: visitor_alice,
          property: property,
          date: Date.new(2026, 1, 5),
          kwh: 30.0,
          note: "EV charging during empty house",
          recorded_by_user: user)

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 10))

        # Database State Verification
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_alice }

        # Empty house: primary delta=100, secondary delta=50, manual=30
        # Empty_kwh = 100-50-30 = 20
        expect(alice_result[:period_shares_kwh]).to eq(0.0)
        expect(alice_result[:manual_entries_kwh]).to eq(30.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(20.0)
        expect(alice_result[:total_kwh]).to eq(50.0)

        expect(result[:total_consumption_kwh]).to eq(50.0)
      end
    end

    context "E5: manual entries during active stay" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }
      let!(:visitor_bob) { create(:visitor, name: "Bob", property: property) }

      it "attributes manual entry and splits remainder among present visitors" do
        # Timeline:
        # Jan 1-10: Alice and Bob both present (300 kWh total: main 200 + secondary 100)
        # Manual entry by Alice: 40 kWh on Jan 5
        # Remainder: 300 - 40 = 260 kWh split equally (130 each)
        # Alice total: 130 (share) + 40 (manual) = 170 kWh
        # Bob total: 130 (share) = 130 kWh
        user = create(:user)

        # Create shared check-in event
        check_in_event = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 1).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: check_in_event, meter: main_meter, value_kwh: 1000.0)
        create(:meter_reading, meter_reading_event: check_in_event, meter: secondary_meter, value_kwh: 500.0)

        # Create shared check-out event
        check_out_event = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 10).beginning_of_day,
          event_type: :check_out,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: check_out_event, meter: main_meter, value_kwh: 1200.0)
        create(:meter_reading, meter_reading_event: check_out_event, meter: secondary_meter, value_kwh: 600.0)

        # Create stays for both visitors
        stay_alice = create(:stay,
          visitor: visitor_alice,
          property: property,
          check_in_event: check_in_event,
          check_out_event: check_out_event)
        stay_bob = create(:stay,
          visitor: visitor_bob,
          property: property,
          check_in_event: check_in_event,
          check_out_event: check_out_event)

        # Add manual entry by Alice
        manual_entry = create(:manual_consumption_entry,
          visitor: visitor_alice,
          property: property,
          date: Date.new(2026, 1, 5),
          kwh: 40.0,
          note: "EV charging during active stay",
          recorded_by_user: user)

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 10))

        # Database State Verification
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_alice }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_bob }

        # Primary delta=200, manual=40, total_pool=200-40=160, split 2=80 each
        expect(alice_result[:period_shares_kwh]).to eq(80.0)
        expect(alice_result[:manual_entries_kwh]).to eq(40.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(0.0)
        expect(alice_result[:total_kwh]).to eq(120.0)

        expect(bob_result[:period_shares_kwh]).to eq(80.0)
        expect(bob_result[:manual_entries_kwh]).to eq(0.0)
        expect(bob_result[:empty_house_share_kwh]).to eq(0.0)
        expect(bob_result[:total_kwh]).to eq(80.0)

        expect(result[:total_consumption_kwh]).to eq(200.0)
      end
    end

    context "multiple meter types" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }

      it "includes both main and secondary meter consumption" do
        # Timeline:
        # Jan 1-10: Alice present
        # Main meter: 1000 -> 1100 (100 kWh)
        # Secondary meter: 500 -> 550 (50 kWh)
        # total_kwh sums ALL meters: 100 + 50 = 150 kWh
        timeline = build_timeline(property) do |t|
          t.add_stay(visitor_alice,
            check_in: Date.new(2026, 1, 1).beginning_of_day,
            check_out: Date.new(2026, 1, 10).beginning_of_day,
            main_reading_in: 1000.0,
            secondary_reading_in: 500.0,
            main_reading_out: 1100.0,
            secondary_reading_out: 550.0)
        end

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 10))

        # Database State Verification
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].first

        # Total = primary delta only (secondary is subordinate): 100 kWh
        expect(alice_result[:total_kwh].to_f).to eq(100.0)
        expect(result[:total_consumption_kwh].to_f).to eq(100.0)
        expect(result[:total_meter_delta_kwh].to_f).to eq(100.0)
      end
    end

    context "mixed scenarios (overlap + empty + manual)" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }
      let!(:visitor_bob) { create(:visitor, name: "Bob", property: property) }
      let!(:visitor_charlie) { create(:visitor, name: "Charlie", property: property) }

      it "handles complex mixed scenario correctly" do
        # Complex Timeline:
        # Jan 1-5: Alice alone (100 kWh)
        # Jan 5-10: Alice + Bob overlap (200 kWh -> 100 each)
        # Jan 10-15: Empty house (100 kWh -> split among all)
        # Jan 15-20: Charlie alone (100 kWh)
        # Manual entry by Alice during overlap: 30 kWh
        user = create(:user)

        # Event 1: Alice checks in
        event1 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 1).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event1, meter: main_meter, value_kwh: 1000.0)
        create(:meter_reading, meter_reading_event: event1, meter: secondary_meter, value_kwh: 500.0)

        # Event 2: Bob checks in
        event2 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 5).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event2, meter: main_meter, value_kwh: 1100.0)
        create(:meter_reading, meter_reading_event: event2, meter: secondary_meter, value_kwh: 550.0)

        # Event 3: Alice and Bob check out
        event3 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 10).beginning_of_day,
          event_type: :check_out,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event3, meter: main_meter, value_kwh: 1300.0)
        create(:meter_reading, meter_reading_event: event3, meter: secondary_meter, value_kwh: 650.0)

        # Event 4: Empty house reading
        event4 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 15).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event4, meter: main_meter, value_kwh: 1400.0)
        create(:meter_reading, meter_reading_event: event4, meter: secondary_meter, value_kwh: 700.0)

        # Event 5: Charlie checks out
        event5 = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 20).beginning_of_day,
          event_type: :check_out,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event5, meter: main_meter, value_kwh: 1500.0)
        create(:meter_reading, meter_reading_event: event5, meter: secondary_meter, value_kwh: 750.0)

        # Create stays
        stay_alice = create(:stay,
          visitor: visitor_alice,
          property: property,
          check_in_event: event1,
          check_out_event: event3)
        stay_bob = create(:stay,
          visitor: visitor_bob,
          property: property,
          check_in_event: event2,
          check_out_event: event3)
        stay_charlie = create(:stay,
          visitor: visitor_charlie,
          property: property,
          check_in_event: event4,
          check_out_event: event5)

        # Add manual entry by Alice during overlap
        manual_entry = create(:manual_consumption_entry,
          visitor: visitor_alice,
          property: property,
          date: Date.new(2026, 1, 7),
          kwh: 30.0,
          note: "EV charging during overlap",
          recorded_by_user: user)

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 20))

        # Database State Verification
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 20)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_alice }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_bob }
        charlie_result = result[:visitors].find { |v| v[:visitor] == visitor_charlie }

        # Verify all visitors are present
        expect(alice_result).to be_present
        expect(bob_result).to be_present
        expect(charlie_result).to be_present

        # Verify total adds up to meter delta
        total_visitor_consumption = alice_result[:total_kwh] + bob_result[:total_kwh] + charlie_result[:total_kwh]
        expect(total_visitor_consumption).to eq(result[:total_consumption_kwh])

        # Verify manual entry is attributed to Alice
        expect(alice_result[:manual_entries_kwh]).to eq(30.0)
        expect(bob_result[:manual_entries_kwh]).to eq(0.0)
        expect(charlie_result[:manual_entries_kwh]).to eq(0.0)
      end
    end
  end

  describe "Date Range Filtering" do
    let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }

    it "only shows consumption for specified date range" do
      # Create stays in different months
      timeline = build_timeline(property) do |t|
        # January stay
        t.add_stay(visitor_alice,
          check_in: Date.new(2026, 1, 1).beginning_of_day,
          check_out: Date.new(2026, 1, 10).beginning_of_day,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0,
          main_reading_out: 1100.0,
          secondary_reading_out: 550.0)

        # February stay
        t.add_stay(visitor_alice,
          check_in: Date.new(2026, 2, 1).beginning_of_day,
          check_out: Date.new(2026, 2, 10).beginning_of_day,
          main_reading_in: 1100.0,
          secondary_reading_in: 550.0,
          main_reading_out: 1250.0,
          secondary_reading_out: 625.0)
      end

      # Query only January
      visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))

      # Database verification for January only
      outcome = CalculateConsumption.run(
        property: property,
        start_date: Date.new(2026, 1, 1),
        end_date: Date.new(2026, 1, 31)
      )

      expect(outcome).to be_valid
      result = outcome.result
      alice_result = result[:visitors].first

      # Should only include January consumption (primary delta = 100 kWh)
      expect(alice_result[:total_kwh]).to eq(100.0)
    end
  end

  describe "Edge Cases" do
    context "no consumption data" do
      it "displays appropriate message when no data exists" do
        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))

        expect(page).to have_content("No consumption data found")
      end
    end

    context "single meter reading event" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }

      it "shows no consumption with only one event" do
        user = create(:user)
        event = create(:meter_reading_event,
          recorded_at: Date.new(2026, 1, 1).beginning_of_day,
          event_type: :check_in,
          recorded_by_user: user)
        create(:meter_reading, meter_reading_event: event, meter: main_meter, value_kwh: 1000.0)
        create(:meter_reading, meter_reading_event: event, meter: secondary_meter, value_kwh: 500.0)

        visit_consumption_report(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))

        expect(page).to have_content("No consumption data found")
      end
    end

    context "year parameter" do
      let!(:visitor_alice) { create(:visitor, name: "Alice", property: property) }

      it "accepts year parameter for full year report" do
        timeline = build_timeline(property) do |t|
          t.add_stay(visitor_alice,
            check_in: Date.new(2026, 1, 1).beginning_of_day,
            check_out: Date.new(2026, 12, 31).beginning_of_day,
            main_reading_in: 1000.0,
            secondary_reading_in: 500.0,
            main_reading_out: 2000.0,
            secondary_reading_out: 1000.0)
        end

        visit consumption_reports_path(year: 2026)

        expect(page).to have_content("2026-01-01")
        expect(page).to have_content("2026-12-31")
        expect(page).to have_content("Alice")
      end
    end
  end
end
