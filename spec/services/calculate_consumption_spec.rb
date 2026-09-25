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

        # Period 1 (Jan 1-5): Alice alone gets 200 kWh (primary delta)
        # Period 2 (Jan 5-10): Empty house pool = primary delta (100 kWh, already includes
        #   the secondary circuit) -> split between Alice and Bob (50 each)
        # Period 3 (Jan 10-15): Bob alone gets 200 kWh (primary delta)
        alice_result = result[:visitors].find { |v| v[:visitor] == visitor_a }
        bob_result = result[:visitors].find { |v| v[:visitor] == visitor_b }

        expect(alice_result[:period_shares_kwh]).to eq(200.0)
        expect(alice_result[:manual_entries_kwh]).to eq(0.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(50.0)
        expect(alice_result[:total_kwh]).to eq(250.0)

        expect(bob_result[:period_shares_kwh]).to eq(200.0)
        expect(bob_result[:manual_entries_kwh]).to eq(0.0)
        expect(bob_result[:empty_house_share_kwh]).to eq(50.0)
        expect(bob_result[:total_kwh]).to eq(250.0)

        expect(result[:total_consumption_kwh]).to eq(500.0)
        expect(result[:total_meter_delta_kwh]).to eq(500.0)
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
          expect(visitor_result[:period_shares_kwh]).to eq(100.0)
          expect(visitor_result[:manual_entries_kwh]).to eq(0.0)
          expect(visitor_result[:empty_house_share_kwh]).to eq(0.0)
          expect(visitor_result[:total_kwh]).to eq(100.0)
        end

        expect(result[:total_consumption_kwh]).to eq(300.0)
        expect(result[:total_meter_delta_kwh]).to eq(300.0)
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

        # Period 1: Alice gets 100 kWh (primary delta)
        # Period 2 & 3: Empty house pool = 100 + 100 = 200 kWh total -> split 100 each
        # Period 4: Bob gets 100 kWh (primary delta)
        expect(alice_result[:period_shares_kwh]).to eq(100.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(100.0)
        expect(alice_result[:total_kwh]).to eq(200.0)

        expect(bob_result[:period_shares_kwh]).to eq(100.0)
        expect(bob_result[:empty_house_share_kwh]).to eq(100.0)
        expect(bob_result[:total_kwh]).to eq(200.0)

        expect(result[:total_consumption_kwh]).to eq(400.0)
        expect(result[:total_meter_delta_kwh]).to eq(400.0)
      end
    end

    context "edge case E4 - manual entry during empty house" do
      it "attributes manual entry directly and deducts from empty house pool" do
        visitor_a = create(:visitor, name: "Alice")

        # Timeline:
        # Jan 1: 1000 kWh (reading, no stay)
        # Jan 5: Manual entry by Alice: 30 kWh on Jan 3
        # Jan 10: 1100 kWh (reading, no stay) -> Period: Empty house pool = primary(100) - manual(30) = 70 kWh
        # Alice gets: 30 (manual) + 70 (empty house share) = 100 kWh
        # total_meter_delta = primary_delta = 100

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
        expect(alice_result[:empty_house_share_kwh]).to eq(70.0)
        expect(alice_result[:total_kwh]).to eq(100.0)

        expect(result[:total_consumption_kwh]).to eq(100.0)
        expect(result[:total_meter_delta_kwh]).to eq(100.0)
      end
    end

    context "edge case E5 - manual entry during active stay" do
      it "attributes manual entry directly and splits remainder among present visitors" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")

        # Timeline:
        # Jan 1: 1000 kWh (Alice and Bob check in)
        # Jan 3: Manual entry by Alice: 40 kWh
        # Jan 10: 1200 kWh (Both check out) -> Period: 200 kWh total, manual 40 kWh
        # Shared pool: 200 - 40 = 160 kWh -> split equally (80 each)
        # Alice total: 80 (period share) + 40 (manual) = 120 kWh
        # Bob total: 80 (period share) = 80 kWh

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

        expect(alice_result[:period_shares_kwh]).to eq(80.0)
        expect(alice_result[:manual_entries_kwh]).to eq(40.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(0.0)
        expect(alice_result[:total_kwh]).to eq(120.0)

        expect(bob_result[:period_shares_kwh]).to eq(80.0)
        expect(bob_result[:manual_entries_kwh]).to eq(0.0)
        expect(bob_result[:empty_house_share_kwh]).to eq(0.0)
        expect(bob_result[:total_kwh]).to eq(80.0)

        expect(result[:total_consumption_kwh]).to eq(200.0)
        expect(result[:total_meter_delta_kwh]).to eq(200.0)
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
        expect(alice_result[:period_shares_kwh]).to eq(500.0)
        expect(alice_result[:manual_entries_kwh]).to eq(0.0)
        expect(alice_result[:empty_house_share_kwh]).to eq(0.0)
        expect(alice_result[:total_kwh]).to eq(500.0)

        expect(result[:total_consumption_kwh]).to eq(500.0)
        expect(result[:total_meter_delta_kwh]).to eq(500.0)
      end
    end

    context "multiple visitors, multiple periods" do
      it "handles complex timeline with multiple visitors and periods" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")
        visitor_c = create(:visitor, name: "Charlie")

        # Timeline:
        # Jan 1: 1000 kWh (Alice checks in)
        # Jan 5: 1100 kWh (Bob checks in) -> Period 1: Alice alone, 100 kWh
        # Jan 10: 1300 kWh (Alice checks out) -> Period 2: Alice + Bob, 200 kWh (100 each)
        # Jan 15: 1500 kWh (Charlie checks in) -> Period 3: Bob alone, 200 kWh
        # Jan 20: 1800 kWh (All check out) -> Period 4: Bob + Charlie, 300 kWh (150 each)

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

        # Alice: 100 (period 1) + 100 (period 2) = 200
        expect(alice_result[:total_kwh]).to eq(200.0)

        # Bob: 100 (period 2) + 200 (period 3) + 150 (period 4) = 450
        expect(bob_result[:total_kwh]).to eq(450.0)

        # Charlie: 150 (period 4) = 150
        expect(charlie_result[:total_kwh]).to eq(150.0)

        expect(result[:total_consumption_kwh]).to eq(800.0)
        expect(result[:total_meter_delta_kwh]).to eq(800.0)
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
        expect(result[:total_meter_delta_kwh]).to eq(100.0) # Meter did increase, but no attribution
      end
    end

    context "sanity check: visitor totals and meter delta" do
      it "attributes every kWh the primary meter measured, so the report shows no mismatch banner" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")

        # Timeline:
        # Jan 1-10: Alice alone, primary delta=350
        # Jan 10-15: Empty house, primary delta=150 (secondary 75 is part of it)
        # Jan 15-20: Bob alone, primary delta=150
        # Empty pool (150) split equally: Alice 75, Bob 75
        # Alice total: 350 + 75 = 425
        # Bob total: 150 + 75 = 225
        # total_consumption = 650 = total_meter_delta

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

        expect(result[:total_meter_delta_kwh]).to eq(650.0)
        expect(result[:total_consumption_kwh]).to eq(650.0)
        expect(result[:visitors].find { |v| v[:visitor] == visitor_a }[:total_kwh]).to eq(425.0)
        expect(result[:visitors].find { |v| v[:visitor] == visitor_b }[:total_kwh]).to eq(225.0)
      end
    end

    context "only the garage (secondary circuit) runs while the house is empty" do
      it "puts the garage kWh into the empty-house pool once, not again when the primary catches up" do
        visitor_a = create(:visitor, name: "Alice")

        # Jan 1: Alice checks in (primary 1000, secondary 500)
        # Jan 5: Alice checks out (primary 1100, secondary 500) -> Alice 100
        # Jan 10: reading, primary unchanged 1100, secondary 504 -> empty house, garage 4 kWh
        # Jan 20: reading, primary 1110, secondary 504 -> empty house; primary catch-up
        #   includes those 4 kWh, so only 10 - 4 = 6 kWh is new
        # Empty pool = 4 + 6 = 10 -> Alice (only visitor with a stay) gets 10
        event1 = create_event(recorded_at: Time.zone.local(2026, 1, 1, 12), main_reading: 1000, secondary_reading: 500)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: event1)
        event2 = create_event(recorded_at: Time.zone.local(2026, 1, 5, 12), main_reading: 1100, secondary_reading: 500, event_type: :check_out)
        stay_a.update!(check_out_event: event2)
        create_event(recorded_at: Time.zone.local(2026, 1, 10, 12), main_reading: 1100, secondary_reading: 504, event_type: :periodic)
        create_event(recorded_at: Time.zone.local(2026, 1, 20, 12), main_reading: 1110, secondary_reading: 504, event_type: :periodic)

        result = CalculateConsumption.run!(property: property, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 31))

        alice = result[:visitors].find { |v| v[:visitor] == visitor_a }
        expect(alice[:period_shares_kwh]).to eq(100.0)
        expect(alice[:empty_house_share_kwh]).to eq(10.0)
        expect(result[:total_consumption_kwh]).to eq(result[:total_meter_delta_kwh])
      end
    end

    context "E10: a one-off guest is archived after departure" do
      let(:visitor_active) { create(:visitor, name: "Alice", status: :active) }
      let(:guest) { create(:visitor, name: "Bob", status: :archived) }

      it "keeps the guest's share with the guest, so archiving never changes what Alice owes" do
        # Jan 1-10: Alice and guest Bob together, 200 kWh, Bob logs 20 kWh EV charging
        #   shared pool = 200 - 20 = 180 -> 90 each; Bob total 90 + 20 = 110
        # Jan 10-15: Bob alone (Alice left), 60 kWh -> Bob
        event1 = create_event(recorded_at: Time.zone.local(2026, 1, 1, 12), main_reading: 1000, secondary_reading: 500)
        stay_active = create(:stay, visitor: visitor_active, property: property, check_in_event: event1)
        stay_guest = create(:stay, visitor: guest, property: property, check_in_event: event1)
        create(:manual_consumption_entry, visitor: guest, property: property, date: Date.new(2026, 1, 5), kwh: 20.0)

        event2 = create_event(recorded_at: Time.zone.local(2026, 1, 10, 12), main_reading: 1200, secondary_reading: 600, event_type: :check_out)
        stay_active.update!(check_out_event: event2)
        event3 = create_event(recorded_at: Time.zone.local(2026, 1, 15, 12), main_reading: 1260, secondary_reading: 600, event_type: :check_out)
        stay_guest.update!(check_out_event: event3)

        result = CalculateConsumption.run!(property: property, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 31))

        alice = result[:visitors].find { |v| v[:visitor] == visitor_active }
        bob = result[:visitors].find { |v| v[:visitor] == guest }

        expect(alice[:total_kwh]).to eq(90.0)
        expect(alice[:empty_house_share_kwh]).to eq(0.0)
        expect(bob[:period_shares_kwh]).to eq(150.0)
        expect(bob[:manual_entries_kwh]).to eq(20.0)
        expect(bob[:total_kwh]).to eq(170.0)
        expect(result[:total_consumption_kwh]).to eq(260.0)
      end
    end

    context "a garage meter is added with a starting value in the middle of a stay" do
      it "charges the full main-meter consumption to the visitor and leaves nothing unreconciled for the next guest" do
        visitor_a = create(:visitor, name: "Alice")
        visitor_b = create(:visitor, name: "Bob")
        garage = create(:meter, property: property, meter_type: :secondary, label: "Garage")

        # Mar 1: Alice in, main 1000
        # Mar 3: admin adds the garage meter, initial 500 (no main reading)
        # Mar 5: Alice out, main 1100, garage 510 -> Alice 100 (the 10 garage kWh are inside the 100)
        # Mar 6 -> Mar 10: Bob, main 1100 -> 1150 -> Bob 50, with nothing subtracted
        check_in = create(:meter_reading_event, recorded_at: Time.zone.local(2026, 3, 1, 12), recorded_by_user: user)
        create(:meter_reading, meter_reading_event: check_in, meter: main_meter, value_kwh: 1000)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: check_in)

        initial = create(:meter_reading_event, recorded_at: Time.zone.local(2026, 3, 3, 12), event_type: :initial, recorded_by_user: user)
        create(:meter_reading, meter_reading_event: initial, meter: garage, value_kwh: 500)

        check_out = create(:meter_reading_event, recorded_at: Time.zone.local(2026, 3, 5, 12), event_type: :check_out, recorded_by_user: user)
        create(:meter_reading, meter_reading_event: check_out, meter: main_meter, value_kwh: 1100)
        create(:meter_reading, meter_reading_event: check_out, meter: garage, value_kwh: 510)
        stay_a.update!(check_out_event: check_out)

        bob_in = create(:meter_reading_event, recorded_at: Time.zone.local(2026, 3, 5, 12), recorded_by_user: user)
        create(:meter_reading, meter_reading_event: bob_in, meter: main_meter, value_kwh: 1100)
        create(:meter_reading, meter_reading_event: bob_in, meter: garage, value_kwh: 510)
        stay_b = create(:stay, visitor: visitor_b, property: property, check_in_event: bob_in)
        bob_out = create(:meter_reading_event, recorded_at: Time.zone.local(2026, 3, 10, 12), event_type: :check_out, recorded_by_user: user)
        create(:meter_reading, meter_reading_event: bob_out, meter: main_meter, value_kwh: 1150)
        create(:meter_reading, meter_reading_event: bob_out, meter: garage, value_kwh: 510)
        stay_b.update!(check_out_event: bob_out)

        result = CalculateConsumption.run!(property: property, start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31))

        expect(result[:visitors].find { |v| v[:visitor] == visitor_a }[:total_kwh]).to eq(100.0)
        expect(result[:visitors].find { |v| v[:visitor] == visitor_b }[:total_kwh]).to eq(50.0)
        expect(result[:total_meter_delta_kwh]).to eq(150.0)
        expect(result[:total_consumption_kwh]).to eq(150.0)
      end
    end

    context "a visitor logs EV charging on the day they check out, then the house stays empty into the next year" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let(:visitor_b) { create(:visitor, name: "Bob") }

      before do
        # Dec 20 - Dec 30: Alice and Bob, 200 kWh; Alice charges 33 kWh on Dec 30
        # Dec 30 - Jan 15: empty house, 40 kWh
        event1 = create_event(recorded_at: Time.zone.local(2025, 12, 20, 12), main_reading: 1000, secondary_reading: 500)
        stay_a = create(:stay, visitor: visitor_a, property: property, check_in_event: event1)
        stay_b = create(:stay, visitor: visitor_b, property: property, check_in_event: event1)
        event2 = create_event(recorded_at: Time.zone.local(2025, 12, 30, 15), main_reading: 1200, secondary_reading: 500, event_type: :check_out)
        stay_a.update!(check_out_event: event2)
        stay_b.update!(check_out_event: event2)
        create_event(recorded_at: Time.zone.local(2026, 1, 15, 12), main_reading: 1240, secondary_reading: 500, event_type: :periodic)
        create(:manual_consumption_entry, visitor: visitor_a, property: property, date: Date.new(2025, 12, 30), kwh: 33.0)
      end

      it "deducts the charge from the stay's shared pool, so Bob doesn't pay for Alice's car" do
        result = CalculateConsumption.run!(property: property, start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 12, 31))

        # shared = 200 - 33 = 167 -> 83.5 each; Alice + 33 manual
        alice = result[:visitors].find { |v| v[:visitor] == visitor_a }
        bob = result[:visitors].find { |v| v[:visitor] == visitor_b }
        expect(alice[:manual_entries_kwh]).to eq(33.0)
        expect(alice[:total_kwh]).to eq(116.5)
        expect(bob[:total_kwh]).to eq(83.5)
      end

      it "doesn't charge the entry again in the next year's report" do
        result = CalculateConsumption.run!(property: property, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31))

        # Only the 40 kWh empty-house period ends in 2026; no visitor had a stay in 2026
        expect(result[:visitors]).to be_empty
        expect(result[:total_meter_delta_kwh]).to eq(40.0)
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
