# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnalyzePeriods do
  let(:property) { create(:property) }
  let(:main_meter) { property.meters.create!(meter_type: "main", label: "Main meter", unit: "kWh") }
  let(:secondary_meter) { property.meters.create!(meter_type: "secondary", label: "Upper floor", unit: "kWh") }
  let(:user) { create(:user) }

  describe "#execute" do
    context "when there are no meter reading events" do
      it "returns an empty array" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.month.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        expect(outcome.result).to eq([])
      end
    end

    context "when there is only one meter reading event" do
      it "returns an empty array" do
        create(:meter_reading_event,
          recorded_at: 2.days.ago,
          property: property,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )

        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        expect(outcome.result).to eq([])
      end
    end

    context "with a single period (2 events)" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let!(:stay_a) do
        create(:stay, :closed,
          visitor: visitor_a,
          property: property,
          check_in_at: 3.days.ago,
          check_out_at: 1.day.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0,
          main_reading_out: 1050.0,
          secondary_reading_out: 525.0
        )
      end

      it "returns a single period with correct attributes" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(1)

        period = periods.first
        expect(period[:start_event]).to eq(stay_a.check_in_event)
        expect(period[:end_event]).to eq(stay_a.check_out_event)
        expect(period[:start_time]).to eq(stay_a.check_in_event.recorded_at)
        expect(period[:end_time]).to eq(stay_a.check_out_event.recorded_at)
        expect(period[:duration_hours]).to be_within(0.1).of(48.0)
        expect(period[:total_kwh]).to eq(BigDecimal("75.0"))
        expect(period[:present_visitors]).to contain_exactly(visitor_a)
        expect(period[:manual_entries]).to eq([])
      end
    end

    context "with multiple periods" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let(:visitor_b) { create(:visitor, name: "Bob") }

      let!(:stay_a) do
        create(:stay, :closed,
          visitor: visitor_a,
          property: property,
          check_in_at: 5.days.ago,
          check_out_at: 4.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0,
          main_reading_out: 1030.0,
          secondary_reading_out: 515.0
        )
      end

      let!(:stay_b) do
        create(:stay, :closed,
          visitor: visitor_b,
          property: property,
          check_in_at: 2.days.ago,
          check_out_at: 1.day.ago,
          main_reading_in: 1030.0,
          secondary_reading_in: 515.0,
          main_reading_out: 1070.0,
          secondary_reading_out: 535.0
        )
      end

      it "returns multiple periods in chronological order" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(3)

        # Period 1: Alice's stay
        period1 = periods[0]
        expect(period1[:start_event]).to eq(stay_a.check_in_event)
        expect(period1[:end_event]).to eq(stay_a.check_out_event)
        expect(period1[:total_kwh]).to eq(BigDecimal("45.0"))
        expect(period1[:present_visitors]).to contain_exactly(visitor_a)

        # Period 2: Empty house gap (Alice's checkout to Bob's checkin)
        period2 = periods[1]
        expect(period2[:start_event]).to eq(stay_a.check_out_event)
        expect(period2[:end_event]).to eq(stay_b.check_in_event)
        expect(period2[:total_kwh]).to eq(BigDecimal("0.0"))
        expect(period2[:present_visitors]).to be_empty

        # Period 3: Bob's stay
        period3 = periods[2]
        expect(period3[:start_event]).to eq(stay_b.check_in_event)
        expect(period3[:end_event]).to eq(stay_b.check_out_event)
        expect(period3[:total_kwh]).to eq(BigDecimal("60.0"))
        expect(period3[:present_visitors]).to contain_exactly(visitor_b)
      end
    end

    context "edge case E1: overlapping stays (multiple visitors present)" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let(:visitor_b) { create(:visitor, name: "Bob") }
      let(:visitor_c) { create(:visitor, name: "Charlie") }

      # Timeline:
      # Day 0: Alice checks in (1000 kWh)
      # Day 1: Bob checks in (1020 kWh) - now Alice + Bob present
      # Day 2: Charlie checks in (1050 kWh) - now Alice + Bob + Charlie present
      # Day 3: Alice checks out (1090 kWh) - now Bob + Charlie present
      # Day 4: Bob checks out (1120 kWh) - now Charlie alone
      # Day 5: Charlie checks out (1140 kWh)

      let!(:event1) do
        create(:meter_reading_event,
          recorded_at: 5.days.ago,
          property: property,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )
      end

      let!(:event2) do
        create(:meter_reading_event,
          recorded_at: 4.days.ago,
          property: property,
          main_reading: 1020.0,
          secondary_reading: 510.0
        )
      end

      let!(:event3) do
        create(:meter_reading_event,
          recorded_at: 3.days.ago,
          property: property,
          main_reading: 1050.0,
          secondary_reading: 525.0
        )
      end

      let!(:event4) do
        create(:meter_reading_event,
          recorded_at: 2.days.ago,
          property: property,
          main_reading: 1090.0,
          secondary_reading: 545.0
        )
      end

      let!(:event5) do
        create(:meter_reading_event,
          recorded_at: 1.day.ago,
          property: property,
          main_reading: 1120.0,
          secondary_reading: 560.0
        )
      end

      let!(:event6) do
        create(:meter_reading_event,
          recorded_at: 12.hours.ago,
          property: property,
          main_reading: 1140.0,
          secondary_reading: 570.0
        )
      end

      let!(:stay_alice) do
        create(:stay,
          visitor: visitor_a,
          property: property,
          check_in_event: event1,
          check_out_event: event4
        )
      end

      let!(:stay_bob) do
        create(:stay,
          visitor: visitor_b,
          property: property,
          check_in_event: event2,
          check_out_event: event5
        )
      end

      let!(:stay_charlie) do
        create(:stay,
          visitor: visitor_c,
          property: property,
          check_in_event: event3,
          check_out_event: event6
        )
      end

      it "correctly identifies present visitors for each overlapping period" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(5)

        # Period 1: event1 -> event2 (Alice alone)
        expect(periods[0][:present_visitors]).to contain_exactly(visitor_a)
        expect(periods[0][:total_kwh]).to eq(BigDecimal("30.0"))

        # Period 2: event2 -> event3 (Alice + Bob)
        expect(periods[1][:present_visitors]).to contain_exactly(visitor_a, visitor_b)
        expect(periods[1][:total_kwh]).to eq(BigDecimal("45.0"))

        # Period 3: event3 -> event4 (Alice + Bob + Charlie)
        expect(periods[2][:present_visitors]).to contain_exactly(visitor_a, visitor_b, visitor_c)
        expect(periods[2][:total_kwh]).to eq(BigDecimal("60.0"))

        # Period 4: event4 -> event5 (Bob + Charlie)
        expect(periods[3][:present_visitors]).to contain_exactly(visitor_b, visitor_c)
        expect(periods[3][:total_kwh]).to eq(BigDecimal("45.0"))

        # Period 5: event5 -> event6 (Charlie alone)
        expect(periods[4][:present_visitors]).to contain_exactly(visitor_c)
        expect(periods[4][:total_kwh]).to eq(BigDecimal("30.0"))
      end
    end

    context "edge case E2: empty house period (no present visitors)" do
      let(:visitor_a) { create(:visitor, name: "Alice") }

      # Timeline:
      # Day 0: Alice checks in (1000 kWh)
      # Day 1: Alice checks out (1050 kWh)
      # Day 2: Empty house meter reading (1070 kWh) - no stays active
      # Day 3: Alice checks in again (1090 kWh)
      # Day 4: Alice checks out (1120 kWh)

      let!(:event1) do
        create(:meter_reading_event,
          recorded_at: 4.days.ago,
          property: property,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )
      end

      let!(:event2) do
        create(:meter_reading_event,
          recorded_at: 3.days.ago,
          property: property,
          main_reading: 1050.0,
          secondary_reading: 525.0
        )
      end

      let!(:event3) do
        create(:meter_reading_event,
          recorded_at: 2.days.ago,
          property: property,
          main_reading: 1070.0,
          secondary_reading: 535.0
        )
      end

      let!(:event4) do
        create(:meter_reading_event,
          recorded_at: 1.day.ago,
          property: property,
          main_reading: 1090.0,
          secondary_reading: 545.0
        )
      end

      let!(:event5) do
        create(:meter_reading_event,
          recorded_at: 12.hours.ago,
          property: property,
          main_reading: 1120.0,
          secondary_reading: 560.0
        )
      end

      let!(:stay1) do
        create(:stay,
          visitor: visitor_a,
          property: property,
          check_in_event: event1,
          check_out_event: event2
        )
      end

      let!(:stay2) do
        create(:stay,
          visitor: visitor_a,
          property: property,
          check_in_event: event4,
          check_out_event: event5
        )
      end

      it "identifies empty house periods with no present visitors" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(4)

        # Period 1: Alice present
        expect(periods[0][:present_visitors]).to contain_exactly(visitor_a)
        expect(periods[0][:total_kwh]).to eq(BigDecimal("75.0"))

        # Period 2: Empty house (event2 -> event3)
        expect(periods[1][:present_visitors]).to be_empty
        expect(periods[1][:total_kwh]).to eq(BigDecimal("30.0"))

        # Period 3: Empty house (event3 -> event4)
        expect(periods[2][:present_visitors]).to be_empty
        expect(periods[2][:total_kwh]).to eq(BigDecimal("30.0"))

        # Period 4: Alice present again
        expect(periods[3][:present_visitors]).to contain_exactly(visitor_a)
        expect(periods[3][:total_kwh]).to eq(BigDecimal("45.0"))
      end
    end

    context "edge case E3: same-day check-in/out (0 duration)" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let(:check_in_time) { 2.days.ago.beginning_of_day + 10.hours }
      let(:check_out_time) { 2.days.ago.beginning_of_day + 10.hours } # Same time

      let!(:stay_a) do
        create(:stay, :closed,
          visitor: visitor_a,
          property: property,
          check_in_at: check_in_time,
          check_out_at: check_out_time,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0,
          main_reading_out: 1000.0, # Same reading
          secondary_reading_out: 500.0
        )
      end

      it "handles zero-duration periods correctly" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(1)

        period = periods.first
        expect(period[:duration_hours]).to eq(0.0)
        expect(period[:total_kwh]).to eq(BigDecimal("0.0"))
        expect(period[:present_visitors]).to contain_exactly(visitor_a)
      end
    end

    context "edge case E11: concurrent events (check-out + check-in at same time)" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let(:visitor_b) { create(:visitor, name: "Bob") }
      let(:swap_time) { 2.days.ago }

      # Timeline:
      # Day 0: Alice checks in (1000 kWh)
      # Day 2: Alice checks out AND Bob checks in (1050 kWh) - same reading
      # Day 4: Bob checks out (1100 kWh)

      let!(:event1) do
        create(:meter_reading_event,
          recorded_at: 4.days.ago,
          property: property,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )
      end

      let!(:event2) do
        create(:meter_reading_event,
          recorded_at: swap_time,
          property: property,
          main_reading: 1050.0,
          secondary_reading: 525.0
        )
      end

      let!(:event3) do
        create(:meter_reading_event,
          recorded_at: 12.hours.ago,
          property: property,
          main_reading: 1100.0,
          secondary_reading: 550.0
        )
      end

      let!(:stay_alice) do
        create(:stay,
          visitor: visitor_a,
          property: property,
          check_in_event: event1,
          check_out_event: event2
        )
      end

      let!(:stay_bob) do
        create(:stay,
          visitor: visitor_b,
          property: property,
          check_in_event: event2,
          check_out_event: event3
        )
      end

      it "handles visitor swap with single meter reading" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(2)

        # Period 1: Alice alone (event1 -> event2)
        expect(periods[0][:present_visitors]).to contain_exactly(visitor_a)
        expect(periods[0][:total_kwh]).to eq(BigDecimal("75.0"))

        # Period 2: Bob alone (event2 -> event3)
        expect(periods[1][:present_visitors]).to contain_exactly(visitor_b)
        expect(periods[1][:total_kwh]).to eq(BigDecimal("75.0"))
      end
    end

    context "manual consumption entries attribution" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let(:visitor_b) { create(:visitor, name: "Bob") }

      let!(:stay_a) do
        create(:stay, :closed,
          visitor: visitor_a,
          property: property,
          check_in_at: 5.days.ago,
          check_out_at: 4.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0,
          main_reading_out: 1050.0,
          secondary_reading_out: 525.0
        )
      end

      let!(:stay_b) do
        create(:stay, :closed,
          visitor: visitor_b,
          property: property,
          check_in_at: 2.days.ago,
          check_out_at: 1.day.ago,
          main_reading_in: 1050.0,
          secondary_reading_in: 525.0,
          main_reading_out: 1100.0,
          secondary_reading_out: 550.0
        )
      end

      # Manual entries during different periods
      let!(:manual_entry_1) do
        create(:manual_consumption_entry,
          visitor: visitor_a,
          property: property,
          date: (5.days.ago + 1.hour).to_date, # Clearly within Alice's stay (5 to 4 days ago)
          kwh: 15.0,
          note: "EV charging during Alice's stay"
        )
      end

      let!(:manual_entry_2) do
        create(:manual_consumption_entry,
          visitor: visitor_b,
          property: property,
          date: 1.8.days.ago.to_date, # Within Bob's stay (2 to 1 days ago), avoiding boundary
          kwh: 20.0,
          note: "EV charging during Bob's stay"
        )
      end

      it "attributes manual entries to the correct periods" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(3)

        # Period 1: Alice's stay - should include manual_entry_1
        period1 = periods[0]
        expect(period1[:manual_entries]).to contain_exactly(manual_entry_1)

        # Period 2: Empty house gap - no manual entries
        period2 = periods[1]
        expect(period2[:manual_entries]).to be_empty

        # Period 3: Bob's stay - should include manual_entry_2
        period3 = periods[2]
        expect(period3[:manual_entries]).to contain_exactly(manual_entry_2)
      end
    end

    context "manual entries during empty house period" do
      let(:visitor_a) { create(:visitor, name: "Alice") }

      # Timeline:
      # Day 0: Alice checks in (1000 kWh)
      # Day 1: Alice checks out (1050 kWh)
      # Day 2: Empty house reading (1070 kWh)
      # Manual entry on Day 1.5 (during empty house period)

      let!(:event1) do
        create(:meter_reading_event,
          recorded_at: 3.days.ago,
          property: property,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )
      end

      let!(:event2) do
        create(:meter_reading_event,
          recorded_at: 2.days.ago,
          property: property,
          main_reading: 1050.0,
          secondary_reading: 525.0
        )
      end

      let!(:event3) do
        create(:meter_reading_event,
          recorded_at: 1.day.ago,
          property: property,
          main_reading: 1070.0,
          secondary_reading: 535.0
        )
      end

      let!(:stay) do
        create(:stay,
          visitor: visitor_a,
          property: property,
          check_in_event: event1,
          check_out_event: event2
        )
      end

      let!(:manual_entry) do
        create(:manual_consumption_entry,
          visitor: visitor_a,
          property: property,
          date: 1.5.days.ago.to_date,
          kwh: 10.0,
          note: "EV charging during empty house"
        )
      end

      it "attributes manual entries to empty house periods" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(2)

        # Period 1: Alice's stay - no manual entries
        expect(periods[0][:present_visitors]).to contain_exactly(visitor_a)
        expect(periods[0][:manual_entries]).to be_empty

        # Period 2: Empty house - should include manual entry
        expect(periods[1][:present_visitors]).to be_empty
        expect(periods[1][:manual_entries]).to contain_exactly(manual_entry)
      end
    end

    context "date range filtering" do
      let(:visitor_a) { create(:visitor, name: "Alice") }

      let!(:stay_old) do
        create(:stay, :closed,
          visitor: visitor_a,
          property: property,
          check_in_at: 60.days.ago,
          check_out_at: 58.days.ago,
          main_reading_in: 800.0,
          secondary_reading_in: 400.0,
          main_reading_out: 850.0,
          secondary_reading_out: 425.0
        )
      end

      let!(:stay_recent) do
        create(:stay, :closed,
          visitor: visitor_a,
          property: property,
          check_in_at: 5.days.ago,
          check_out_at: 3.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0,
          main_reading_out: 1050.0,
          secondary_reading_out: 525.0
        )
      end

      it "only includes events within the specified date range" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(1)

        # Should only include the recent stay
        period = periods.first
        expect(period[:start_event]).to eq(stay_recent.check_in_event)
        expect(period[:end_event]).to eq(stay_recent.check_out_event)
      end
    end

    context "partial overlaps vs full overlaps" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let(:visitor_b) { create(:visitor, name: "Bob") }

      # Timeline:
      # Day 0: Alice checks in (1000 kWh)
      # Day 1: Bob checks in (1020 kWh) - Alice + Bob overlap starts
      # Day 2: Alice checks out (1050 kWh) - Bob continues alone
      # Day 3: Bob checks out (1080 kWh)

      let!(:event1) do
        create(:meter_reading_event,
          recorded_at: 4.days.ago,
          property: property,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )
      end

      let!(:event2) do
        create(:meter_reading_event,
          recorded_at: 3.days.ago,
          property: property,
          main_reading: 1020.0,
          secondary_reading: 510.0
        )
      end

      let!(:event3) do
        create(:meter_reading_event,
          recorded_at: 2.days.ago,
          property: property,
          main_reading: 1050.0,
          secondary_reading: 525.0
        )
      end

      let!(:event4) do
        create(:meter_reading_event,
          recorded_at: 1.day.ago,
          property: property,
          main_reading: 1080.0,
          secondary_reading: 540.0
        )
      end

      let!(:stay_alice) do
        create(:stay,
          visitor: visitor_a,
          property: property,
          check_in_event: event1,
          check_out_event: event3
        )
      end

      let!(:stay_bob) do
        create(:stay,
          visitor: visitor_b,
          property: property,
          check_in_event: event2,
          check_out_event: event4
        )
      end

      it "correctly identifies partial vs full overlaps" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(3)

        # Period 1: event1 -> event2 (Alice alone)
        expect(periods[0][:present_visitors]).to contain_exactly(visitor_a)
        expect(periods[0][:total_kwh]).to eq(BigDecimal("30.0"))

        # Period 2: event2 -> event3 (Alice + Bob overlap)
        expect(periods[1][:present_visitors]).to contain_exactly(visitor_a, visitor_b)
        expect(periods[1][:total_kwh]).to eq(BigDecimal("45.0"))

        # Period 3: event3 -> event4 (Bob alone)
        expect(periods[2][:present_visitors]).to contain_exactly(visitor_b)
        expect(periods[2][:total_kwh]).to eq(BigDecimal("45.0"))
      end
    end

    context "when stay has open check_out (visitor currently present)" do
      let(:visitor_a) { create(:visitor, name: "Alice") }

      let!(:event1) do
        create(:meter_reading_event,
          recorded_at: 3.days.ago,
          property: property,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )
      end

      let!(:event2) do
        create(:meter_reading_event,
          recorded_at: 1.day.ago,
          property: property,
          main_reading: 1050.0,
          secondary_reading: 525.0
        )
      end

      let!(:stay_open) do
        create(:stay,
          visitor: visitor_a,
          property: property,
          check_in_event: event1,
          check_out_event: nil # Still open
        )
      end

      it "includes visitor with open stay in present_visitors" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(1)

        # Period from event1 to event2 should include Alice (who is still checked in)
        period = periods.first
        expect(period[:present_visitors]).to contain_exactly(visitor_a)
        expect(period[:total_kwh]).to eq(BigDecimal("75.0"))
      end
    end

    context "with missing secondary meter readings" do
      let(:visitor_a) { create(:visitor, name: "Alice") }

      let!(:event1) do
        create(:meter_reading_event,
          recorded_at: 2.days.ago,
          property: property,
          main_reading: 1000.0
          # No secondary reading
        )
      end

      let!(:event2) do
        create(:meter_reading_event,
          recorded_at: 1.day.ago,
          property: property,
          main_reading: 1050.0
          # No secondary reading
        )
      end

      let!(:stay) do
        create(:stay,
          visitor: visitor_a,
          property: property,
          check_in_event: event1,
          check_out_event: event2
        )
      end

      it "handles missing secondary readings gracefully" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        expect(periods.size).to eq(1)

        period = periods.first
        expect(period[:total_kwh]).to eq(BigDecimal("50.0"))
        expect(period[:present_visitors]).to contain_exactly(visitor_a)
      end
    end
  end
end
