# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalculateConsumption, type: :service do
  let(:property) { create(:property) }
  let(:main_meter) { create(:meter, property: property, meter_type: :main, label: "Main meter") }
  let(:secondary_meter) { create(:meter, property: property, meter_type: :secondary, label: "Upper floor meter") }
  let(:user) { create(:user) }

  # Helper to create a meter reading event with readings
  def create_event(recorded_at:, main_reading:, secondary_reading:, event_type: :check_in)
    event = create(:meter_reading_event,
      recorded_at: recorded_at,
      event_type: event_type,
      recorded_by_user: user)

    create(:meter_reading,
      meter_reading_event: event,
      meter: main_meter,
      value_kwh: main_reading)

    create(:meter_reading,
      meter_reading_event: event,
      meter: secondary_meter,
      value_kwh: secondary_reading)

    event
  end

  describe "#execute" do
    context "happy path - mixed periods (occupied + empty)" do
      it "calculates consumption correctly with occupied and empty house periods" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")

        # Timeline:
        # Jan 1: 1000 kWh (Alice checks in)
        # Jan 5: 1200 kWh (Alice checks out) -> Period 1: Alice alone, 200 kWh
        # Jan 10: 1300 kWh (Bob checks in) -> Period 2: Empty house, 100 kWh
        # Jan 15: 1500 kWh (Bob checks out) -> Period 3: Bob alone, 200 kWh

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: event1)

        event2 = create_event(recorded_at: Date.new(2026, 1, 5).beginning_of_day, main_reading: 1200, secondary_reading: 600, event_type: :check_out)
        stay_a.update!(check_out_event: event2)

        event3 = create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1300, secondary_reading: 650)
        stay_b = create(:stay, visitor: visitor_b, property: property, check_in_event: event3)

        event4 = create_event(recorded_at: Date.new(2026, 1, 15).beginning_of_day, main_reading: 1500, secondary_reading: 750, event_type: :check_out)
        stay_b.update!(check_out_event: event4)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 15)
        )

        expect(outcome).to be_valid
        result = outcome.result

        # Period 1 (Jan 1-5): Alice alone gets 300 kWh
        # Period 2 (Jan 5-10): Empty house 150 kWh -> split between Alice and Bob (75 each)
        # Period 3 (Jan 10-15): Bob alone gets 300 kWh
        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_a }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_b }

        expect(alice_result[:period_shares_kwh]).to eq(300.0)
        expect(alice_result[:manual_entries_kwh]).to eq(0.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(75.0)
        expect(alice_result[:total_kwh]).to eq(375.0)

        expect(bob_result[:period_shares_kwh]).to eq(300.0)
        expect(bob_result[:manual_entries_kwh]).to eq(0.0)
        expect(bob_result[:empty_house_share_kwh]).to eq(75.0)
        expect(bob_result[:total_kwh]).to eq(375.0)

        expect(result[:total_consumption_kwh]).to eq(750.0)
        expect(result[:total_meter_delta_kwh]).to eq(750.0)
      end
    end

    context "edge case E1 - overlapping stays (equal split)" do
      it "splits consumption equally among all present visitors" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")
        visitor_c = create(:visitor, name: "Charlie")

        # Timeline:
        # Jan 1: 1000 kWh (Alice, Bob, Charlie check in)
        # Jan 10: 1300 kWh (All check out) -> Period: 3 visitors, 450 kWh total, 150 kWh each

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: event1)
        stay_b = create(:stay, visitor: visitor_b, property: property, check_in_event: event1)
        stay_c = create(:stay, visitor: visitor_c, property: property, check_in_event: event1)

        event2 = create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1300, secondary_reading: 650, event_type: :check_out)
        stay_a.update!(check_out_event: event2)
        stay_b.update!(check_out_event: event2)
        stay_c.update!(check_out_event: event2)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result

        result[:visitors].each do |visitor_result|
          expect(visitor_result[:period_shares_kwh]).to eq(150.0)
          expect(visitor_result[:manual_entries_kwh]).to eq(0.0)
          expect(visitor_result[:empty_house_share_kwh]).to eq(0.0)
          expect(visitor_result[:total_kwh]).to eq(150.0)
        end

        expect(result[:total_consumption_kwh]).to eq(450.0)
        expect(result[:total_meter_delta_kwh]).to eq(450.0)
      end
    end

    context "edge case E2 - empty house periods (distributed equally)" do
      it "distributes empty house consumption equally among all visitors with stays" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")

        # Timeline:
        # Jan 1: 1000 kWh (Alice checks in)
        # Jan 5: 1100 kWh (Alice checks out) -> Period 1: Alice alone, 100 kWh
        # Jan 10: 1200 kWh (Empty house) -> Period 2: Empty house, 100 kWh
        # Jan 15: 1300 kWh (Bob checks in) -> Period 3: Empty house, 100 kWh
        # Jan 20: 1400 kWh (Bob checks out) -> Period 4: Bob alone, 100 kWh

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: event1)

        event2 = create_event(recorded_at: Date.new(2026, 1, 5).beginning_of_day, main_reading: 1100, secondary_reading: 550, event_type: :check_out)
        stay_a.update!(check_out_event: event2)

        event3 = create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1200, secondary_reading: 600)

        event4 = create_event(recorded_at: Date.new(2026, 1, 15).beginning_of_day, main_reading: 1300, secondary_reading: 650)
        stay_b = create(:stay, visitor: visitor_b, property: property, check_in_event: event4)

        event5 = create_event(recorded_at: Date.new(2026, 1, 20).beginning_of_day, main_reading: 1400, secondary_reading: 700, event_type: :check_out)
        stay_b.update!(check_out_event: event5)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 20)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_a }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_b }

        # Period 1: Alice gets 150 kWh
        # Period 2 & 3: Empty house 300 kWh total -> split 150 each
        # Period 4: Bob gets 150 kWh
        expect(alice_result[:period_shares_kwh]).to eq(150.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(150.0)
        expect(alice_result[:total_kwh]).to eq(300.0)

        expect(bob_result[:period_shares_kwh]).to eq(150.0)
        expect(bob_result[:empty_house_share_kwh]).to eq(150.0)
        expect(bob_result[:total_kwh]).to eq(300.0)

        expect(result[:total_consumption_kwh]).to eq(600.0)
        expect(result[:total_meter_delta_kwh]).to eq(600.0)
      end
    end

    context "edge case E4 - manual entry during empty house" do
      it "attributes manual entry directly and deducts from empty house pool" do
        visitor_a = create(:visitor, name: "Alice")

        # Timeline:
        # Jan 1: 1000 kWh (reading, no stay)
        # Jan 5: Manual entry by Alice: 30 kWh on Jan 3
        # Jan 10: 1100 kWh (reading, no stay) -> Period: Empty house 150 kWh, manual 30 kWh
        # Shared pool: 150 - 30 = 120 kWh -> goes to unattributed, then to Alice
        # Alice total: 30 (manual) + 120 (empty house share) = 150 kWh

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        event2 = create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1100, secondary_reading: 550)

        manual_entry = create(:manual_consumption_entry,
          visitor: visitor_a,
          property: property,
          date: Date.new(2026, 1, 3),
          kwh: 30.0,
          note: "EV charging")

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_a }

        expect(alice_result[:period_shares_kwh]).to eq(0.0)
        expect(alice_result[:manual_entries_kwh]).to eq(30.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(120.0)
        expect(alice_result[:total_kwh]).to eq(150.0)

        expect(result[:total_consumption_kwh]).to eq(150.0)
        expect(result[:total_meter_delta_kwh]).to eq(150.0)
      end
    end

    context "edge case E5 - manual entry during active stay" do
      it "attributes manual entry directly and splits remainder among present visitors" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")

        # Timeline:
        # Jan 1: 1000 kWh (Alice and Bob check in)
        # Jan 3: Manual entry by Alice: 40 kWh
        # Jan 10: 1200 kWh (Both check out) -> Period: 300 kWh total, manual 40 kWh
        # Shared pool: 300 - 40 = 260 kWh -> split equally (130 each)
        # Alice total: 130 (period share) + 40 (manual) = 170 kWh
        # Bob total: 130 (period share) = 130 kWh

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: event1)
        stay_b = create(:stay, visitor: visitor_b, property: property, check_in_event: event1)

        manual_entry = create(:manual_consumption_entry,
          visitor: visitor_a,
          property: property,
          date: Date.new(2026, 1, 3),
          kwh: 40.0,
          note: "EV charging")

        event2 = create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1200, secondary_reading: 600, event_type: :check_out)
        stay_a.update!(check_out_event: event2)
        stay_b.update!(check_out_event: event2)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_a }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_b }

        expect(alice_result[:period_shares_kwh]).to eq(130.0)
        expect(alice_result[:manual_entries_kwh]).to eq(40.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(0.0)
        expect(alice_result[:total_kwh]).to eq(170.0)

        expect(bob_result[:period_shares_kwh]).to eq(130.0)
        expect(bob_result[:manual_entries_kwh]).to eq(0.0)
        expect(bob_result[:empty_house_share_kwh]).to eq(0.0)
        expect(bob_result[:total_kwh]).to eq(130.0)

        expect(result[:total_consumption_kwh]).to eq(300.0)
        expect(result[:total_meter_delta_kwh]).to eq(300.0)
      end
    end

    context "single visitor entire period" do
      it "allocates all consumption to the single visitor" do
        visitor_a = create(:visitor, name: "Alice")

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: event1)

        event2 = create_event(recorded_at: Date.new(2026, 1, 31).end_of_day, main_reading: 1500, secondary_reading: 750, event_type: :check_out)
        stay_a.update!(check_out_event: event2)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 31)
        )

        expect(outcome).to be_valid
        result = outcome.result

        expect(result[:visitors].size).to eq(1)
        alice_result = result[:visitors].first

        expect(alice_result[:visitor]).to eq(visitor_a)
        expect(alice_result[:period_shares_kwh]).to eq(750.0)
        expect(alice_result[:manual_entries_kwh]).to eq(0.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(0.0)
        expect(alice_result[:total_kwh]).to eq(750.0)

        expect(result[:total_consumption_kwh]).to eq(750.0)
        expect(result[:total_meter_delta_kwh]).to eq(750.0)
      end
    end

    context "multiple visitors, multiple periods" do
      it "handles complex timeline with multiple visitors and periods" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")
        visitor_c = create(:visitor, name: "Charlie")

        # Timeline:
        # Jan 1: 1000 kWh (Alice checks in)
        # Jan 5: 1100 kWh (Bob checks in) -> Period 1: Alice alone, 150 kWh
        # Jan 10: 1300 kWh (Alice checks out) -> Period 2: Alice + Bob, 300 kWh (150 each)
        # Jan 15: 1500 kWh (Charlie checks in) -> Period 3: Bob alone, 300 kWh
        # Jan 20: 1800 kWh (All check out) -> Period 4: Bob + Charlie, 450 kWh (225 each)

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: event1)

        event2 = create_event(recorded_at: Date.new(2026, 1, 5).beginning_of_day, main_reading: 1100, secondary_reading: 550)
        stay_b = create(:stay, visitor: visitor_b, property: property, check_in_event: event2)

        event3 = create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1300, secondary_reading: 650, event_type: :check_out)
        stay_a.update!(check_out_event: event3)

        event4 = create_event(recorded_at: Date.new(2026, 1, 15).beginning_of_day, main_reading: 1500, secondary_reading: 750)
        stay_c = create(:stay, visitor: visitor_c, property: property, check_in_event: event4)

        event5 = create_event(recorded_at: Date.new(2026, 1, 20).beginning_of_day, main_reading: 1800, secondary_reading: 900, event_type: :check_out)
        stay_b.update!(check_out_event: event5)
        stay_c.update!(check_out_event: event5)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 20)
        )

        expect(outcome).to be_valid
        result = outcome.result

        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_a }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_b }
        charlie_result = result[:visitors].find { |v| v[:visitor] == visitor_c }

        # Alice: 150 (period 1) + 150 (period 2) = 300
        expect(alice_result[:total_kwh]).to eq(300.0)

        # Bob: 150 (period 2) + 300 (period 3) + 225 (period 4) = 675
        expect(bob_result[:total_kwh]).to eq(675.0)

        # Charlie: 225 (period 4) = 225
        expect(charlie_result[:total_kwh]).to eq(225.0)

        expect(result[:total_consumption_kwh]).to eq(1200.0)
        expect(result[:total_meter_delta_kwh]).to eq(1200.0)
      end
    end

    context "no stays (all empty house)" do
      it "returns zero consumption when no visitors had stays" do
        # Timeline with readings but no stays
        create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1100, secondary_reading: 550)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10)
        )

        expect(outcome).to be_valid
        result = outcome.result

        expect(result[:visitors]).to be_empty
        expect(result[:total_consumption_kwh]).to eq(0.0)
        expect(result[:total_meter_delta_kwh]).to eq(150.0) # Meter did increase, but no attribution
      end
    end

    context "sanity check: total_kwh == meter delta" do
      it "ensures sum of visitor totals equals meter delta" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: event1)

        event2 = create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1350, secondary_reading: 675, event_type: :check_out)
        stay_a.update!(check_out_event: event2)

        event3 = create_event(recorded_at: Date.new(2026, 1, 15).beginning_of_day, main_reading: 1500, secondary_reading: 750)
        stay_b = create(:stay, visitor: visitor_b, property: property, check_in_event: event3)

        event4 = create_event(recorded_at: Date.new(2026, 1, 20).beginning_of_day, main_reading: 1650, secondary_reading: 825, event_type: :check_out)
        stay_b.update!(check_out_event: event4)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 20)
        )

        expect(outcome).to be_valid
        result = outcome.result

        expect(result[:total_consumption_kwh]).to eq(result[:total_meter_delta_kwh])
        expect(result[:total_meter_delta_kwh]).to eq(975.0)
      end
    end

    context "archived visitor exclusion/inclusion" do
      it "excludes archived visitors by default" do
        visitor_active = create(:visitor, name: "Alice", status: :active)
        visitor_archived = create(:visitor, name: "Bob", status: :archived)

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        stay_active = create(:stay, visitor: visitor_active, property: property, check_in_event: event1)
        stay_archived = create(:stay, visitor: visitor_archived, property: property, check_in_event: event1)

        event2 = create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1200, secondary_reading: 600, event_type: :check_out)
        stay_active.update!(check_out_event: event2)
        stay_archived.update!(check_out_event: event2)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10),
          include_archived_visitors: false
        )

        expect(outcome).to be_valid
        result = outcome.result

        expect(result[:visitors].size).to eq(1)
        expect(result[:visitors].first[:visitor]).to eq(visitor_active)
        expect(result[:visitors].first[:total_kwh]).to eq(300.0)
      end

      it "includes archived visitors when flag is true" do
        visitor_active = create(:visitor, name: "Alice", status: :active)
        visitor_archived = create(:visitor, name: "Bob", status: :archived)

        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        stay_active = create(:stay, visitor: visitor_active, property: property, check_in_event: event1)
        stay_archived = create(:stay, visitor: visitor_archived, property: property, check_in_event: event1)

        event2 = create_event(recorded_at: Date.new(2026, 1, 10).beginning_of_day, main_reading: 1200, secondary_reading: 600, event_type: :check_out)
        stay_active.update!(check_out_event: event2)
        stay_archived.update!(check_out_event: event2)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 10),
          include_archived_visitors: true
        )

        expect(outcome).to be_valid
        result = outcome.result

        expect(result[:visitors].size).to eq(2)
        expect(result[:visitors].map { |v| v[:visitor] }).to contain_exactly(visitor_active, visitor_archived)

        # Each gets 150 kWh (300 total split equally)
        result[:visitors].each do |visitor_result|
          expect(visitor_result[:total_kwh]).to eq(150.0)
        end
      end
    end

    context "validation errors" do
      it "validates that end_date is after start_date" do
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 10),
          end_date: Date.new(2026, 1, 1)
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:end_date]).to include("must be after or equal to start_date")
      end

      it "accepts equal start and end dates" do
        event1 = create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)
        event2 = create_event(recorded_at: Date.new(2026, 1, 1).end_of_day, main_reading: 1100, secondary_reading: 550)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 1)
        )

        expect(outcome).to be_valid
      end
    end

    context "empty result" do
      it "returns empty result when no meter reading events exist" do
        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 31)
        )

        expect(outcome).to be_valid
        result = outcome.result

        expect(result[:visitors]).to be_empty
        expect(result[:total_consumption_kwh]).to eq(0.0)
        expect(result[:total_meter_delta_kwh]).to eq(0.0)
      end

      it "returns empty result when only one event exists" do
        create_event(recorded_at: Date.new(2026, 1, 1).beginning_of_day, main_reading: 1000, secondary_reading: 500)

        outcome = CalculateConsumption.run(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 1, 31)
        )

        expect(outcome).to be_valid
        result = outcome.result

        expect(result[:visitors]).to be_empty
        expect(result[:total_consumption_kwh]).to eq(0.0)
        expect(result[:total_meter_delta_kwh]).to eq(0.0)
      end
    end
  end
end
