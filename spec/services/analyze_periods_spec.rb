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
        expect(period[:total_kwh]).to eq(BigDecimal("50.0"))
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
        expect(period1[:total_kwh]).to eq(BigDecimal("30.0"))
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
        expect(period3[:total_kwh]).to eq(BigDecimal("40.0"))
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
        expect(periods[0][:total_kwh]).to eq(BigDecimal("20.0"))

        # Period 2: event2 -> event3 (Alice + Bob)
        expect(periods[1][:present_visitors]).to contain_exactly(visitor_a, visitor_b)
        expect(periods[1][:total_kwh]).to eq(BigDecimal("30.0"))

        # Period 3: event3 -> event4 (Alice + Bob + Charlie)
        expect(periods[2][:present_visitors]).to contain_exactly(visitor_a, visitor_b, visitor_c)
        expect(periods[2][:total_kwh]).to eq(BigDecimal("40.0"))

        # Period 4: event4 -> event5 (Bob + Charlie)
        expect(periods[3][:present_visitors]).to contain_exactly(visitor_b, visitor_c)
        expect(periods[3][:total_kwh]).to eq(BigDecimal("30.0"))

        # Period 5: event5 -> event6 (Charlie alone)
        expect(periods[4][:present_visitors]).to contain_exactly(visitor_c)
        expect(periods[4][:total_kwh]).to eq(BigDecimal("20.0"))
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
        expect(periods[0][:total_kwh]).to eq(BigDecimal("50.0"))

        # Period 2: Empty house (event2 -> event3)
        expect(periods[1][:present_visitors]).to be_empty
        expect(periods[1][:total_kwh]).to eq(BigDecimal("20.0"))

        # Period 3: Empty house (event3 -> event4)
        expect(periods[2][:present_visitors]).to be_empty
        expect(periods[2][:total_kwh]).to eq(BigDecimal("20.0"))

        # Period 4: Alice present again
        expect(periods[3][:present_visitors]).to contain_exactly(visitor_a)
        expect(periods[3][:total_kwh]).to eq(BigDecimal("30.0"))
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
        expect(periods[0][:total_kwh]).to eq(BigDecimal("50.0"))

        # Period 2: Bob alone (event2 -> event3)
        expect(periods[1][:present_visitors]).to contain_exactly(visitor_b)
        expect(periods[1][:total_kwh]).to eq(BigDecimal("50.0"))
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
          date: 5.days.ago.to_date, # Clearly within Alice's stay (5 to 4 days ago)
          kwh: 15.0,
          note: "EV charging during Alice's stay"
        )
      end

      let!(:manual_entry_2) do
        create(:manual_consumption_entry,
          visitor: visitor_b,
          property: property,
          date: 2.days.ago.to_date, # Within Bob's stay (2 to 1 days ago), uses start date
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
          date: 1.day.ago.to_date, # Day of the empty-house closing reading; Alice isn't present then
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

      it "includes boundary event from before the date range plus in-range events" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result
        # 2 periods: boundary (old checkout) -> recent check_in, then recent check_in -> recent check_out
        expect(periods.size).to eq(2)

        # Period 1: boundary event (old checkout) to recent check_in — empty house gap
        expect(periods[0][:start_event]).to eq(stay_old.check_out_event)
        expect(periods[0][:end_event]).to eq(stay_recent.check_in_event)
        expect(periods[0][:present_visitors]).to be_empty

        # Period 2: recent stay
        expect(periods[1][:start_event]).to eq(stay_recent.check_in_event)
        expect(periods[1][:end_event]).to eq(stay_recent.check_out_event)
      end
    end

    context "boundary event: last event before date range creates leading period" do
      let(:visitor_a) { create(:visitor, name: "Alice") }

      # Simulates: previous year's last event, then a gap, then new year's events.
      # The consumption between the boundary event and the first in-range event
      # is empty-house consumption that must be captured.

      let!(:boundary_event) do
        create(:meter_reading_event,
          recorded_at: 30.days.ago, # before the date range
          property: property,
          main_reading: 1000.0,
          secondary_reading: 500.0
        )
      end

      let!(:stay_a) do
        create(:stay, :closed,
          visitor: visitor_a,
          property: property,
          check_in_at: 5.days.ago,
          check_out_at: 3.days.ago,
          main_reading_in: 1005.0, # 5 kWh empty house gap
          secondary_reading_in: 500.0,
          main_reading_out: 1015.0,
          secondary_reading_out: 500.0
        )
      end

      it "includes the boundary event to capture empty-house consumption before the first in-range event" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome).to be_valid
        periods = outcome.result

        # Should have 2 periods:
        # 1. boundary_event -> check_in (5 kWh empty house)
        # 2. check_in -> check_out (10 kWh, Alice present)
        expect(periods.size).to eq(2)

        # Period 1: empty house gap from boundary event to check-in
        expect(periods[0][:start_event]).to eq(boundary_event)
        expect(periods[0][:present_visitors]).to be_empty
        expect(periods[0][:total_kwh]).to eq(BigDecimal("5.0"))

        # Period 2: Alice's stay
        expect(periods[1][:present_visitors]).to contain_exactly(visitor_a)
        expect(periods[1][:total_kwh]).to eq(BigDecimal("10.0"))
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
        expect(periods[0][:total_kwh]).to eq(BigDecimal("20.0"))

        # Period 2: event2 -> event3 (Alice + Bob overlap)
        expect(periods[1][:present_visitors]).to contain_exactly(visitor_a, visitor_b)
        expect(periods[1][:total_kwh]).to eq(BigDecimal("30.0"))

        # Period 3: event3 -> event4 (Bob alone)
        expect(periods[2][:present_visitors]).to contain_exactly(visitor_b)
        expect(periods[2][:total_kwh]).to eq(BigDecimal("30.0"))
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
        expect(period[:total_kwh]).to eq(BigDecimal("50.0"))
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

    context "legacy stay left open after its check-in event was deleted by older code" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let(:visitor_b) { create(:visitor, name: "Bob") }
      let!(:orphan_stay) do
        create(:stay, :open, visitor: visitor_a, property: property, check_in_at: 5.days.ago,
               main_reading_in: 1000.0, secondary_reading_in: 500.0)
          .tap { |s| s.check_in_event.discard! }
      end
      let!(:stay_b) do
        create(:stay, :closed, visitor: visitor_b, property: property,
               check_in_at: 3.days.ago, check_out_at: 1.day.ago,
               main_reading_in: 1100.0, secondary_reading_in: 550.0,
               main_reading_out: 1200.0, secondary_reading_out: 600.0)
      end

      it "does not bill the orphaned visitor for periods after the deleted check-in" do
        outcome = described_class.run(
          property: property,
          date_range: { start_date: 1.week.ago.to_date, end_date: Date.current }
        )

        expect(outcome.result.flat_map { |p| p[:present_visitors] }).not_to include(visitor_a)
      end
    end

    context "an admin adds a meter with a starting value while a visitor is staying" do
      let(:visitor_a) { create(:visitor, name: "Alice") }

      def reading_event(at, type, readings)
        event = create(:meter_reading_event, recorded_at: at, event_type: type, recorded_by_user: user)
        readings.each { |meter, value| create(:meter_reading, meter_reading_event: event, meter: meter, value_kwh: value) }
        event
      end

      let!(:check_in) { reading_event(Time.zone.local(2026, 3, 1, 12), :check_in, main_meter => 1000) }

      before do
        stay = create(:stay, visitor: visitor_a, property: property, check_in_event: check_in)
        # Garage meter installed mid-stay; its "initial" event carries only its own reading
        reading_event(Time.zone.local(2026, 3, 3, 12), :initial, secondary_meter => 500)
        check_out = reading_event(Time.zone.local(2026, 3, 5, 12), :check_out, main_meter => 1100, secondary_meter => 510)
        stay.update!(check_out_event: check_out)
      end

      it "keeps the stay as one period so the main meter's 100 kWh is not lost at the initial event" do
        periods = described_class.run!(property: property, date_range: { start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31) })

        expect(periods.size).to eq(1)
        expect(periods.first[:primary_delta]).to eq(BigDecimal("100"))
        expect(periods.first[:present_visitors]).to contain_exactly(visitor_a)
      end

      it "measures the new meter from its initial value, so the garage's 10 kWh is still seen" do
        periods = described_class.run!(property: property, date_range: { start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31) })

        expect(periods.first[:secondary_delta]).to eq(BigDecimal("10"))
      end
    end

    context "a second main meter (NT tariff) is added with a starting value mid-stay" do
      let(:nt_meter) { property.meters.create!(meter_type: "main", label: "NT", unit: "kWh") }

      it "counts VT across the initial event and NT from its baseline" do
        visitor = create(:visitor)
        check_in = create(:meter_reading_event, recorded_at: Time.zone.local(2026, 3, 1, 12), recorded_by_user: user)
        create(:meter_reading, meter_reading_event: check_in, meter: main_meter, value_kwh: 1000)
        stay = create(:stay, visitor: visitor, property: property, check_in_event: check_in)

        initial = create(:meter_reading_event, recorded_at: Time.zone.local(2026, 3, 3, 12), event_type: :initial, recorded_by_user: user)
        create(:meter_reading, meter_reading_event: initial, meter: nt_meter, value_kwh: 200)

        check_out = create(:meter_reading_event, recorded_at: Time.zone.local(2026, 3, 5, 12), event_type: :check_out, recorded_by_user: user)
        create(:meter_reading, meter_reading_event: check_out, meter: main_meter, value_kwh: 1080)
        create(:meter_reading, meter_reading_event: check_out, meter: nt_meter, value_kwh: 230)
        stay.update!(check_out_event: check_out)

        periods = described_class.run!(property: property, date_range: { start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31) })

        # VT 80 + NT 30
        expect(periods.map { |p| p[:primary_delta] }).to eq([ BigDecimal("110") ])
      end
    end

    context "E8: the secondary meter was not read at one event" do
      it "charges the secondary consumption to the period in which it is next read instead of dropping it" do
        e1 = create(:meter_reading_event, recorded_at: Time.zone.local(2026, 4, 1, 12), property: property, main_reading: 1000, secondary_reading: 500)
        create(:meter_reading_event, recorded_at: Time.zone.local(2026, 4, 5, 12), property: property, main_reading: 1040)
        create(:meter_reading_event, recorded_at: Time.zone.local(2026, 4, 9, 12), property: property, main_reading: 1090, secondary_reading: 512)

        periods = described_class.run!(property: property, date_range: { start_date: Date.new(2026, 4, 1), end_date: Date.new(2026, 4, 30) })

        expect(periods.first[:start_event]).to eq(e1)
        expect(periods.map { |p| p[:secondary_delta] }).to eq([ BigDecimal("0"), BigDecimal("12") ])
        expect(periods.map { |p| p[:primary_delta] }).to eq([ BigDecimal("40"), BigDecimal("50") ])
      end
    end

    context "a manual entry is dated on a day that two periods share" do
      let(:visitor_a) { create(:visitor, name: "Alice") }
      let(:visitor_b) { create(:visitor, name: "Bob") }

      # Jun 1 reading -> empty house -> Alice Jun 10 12:00 .. Jun 20 09:00 -> empty house -> Jul 1 reading
      # periods: [0] Jun 1-10 empty, [1] Alice's stay, [2] Jun 20 - Jul 1 empty
      let!(:opening_reading) do
        create(:meter_reading_event, recorded_at: Time.zone.local(2026, 6, 1, 12), property: property,
          main_reading: 990, secondary_reading: 500)
      end
      let!(:stay_a) do
        create(:stay, :closed, visitor: visitor_a, property: property,
          check_in_at: Time.zone.local(2026, 6, 10, 12), check_out_at: Time.zone.local(2026, 6, 20, 9),
          main_reading_in: 1000, secondary_reading_in: 500, main_reading_out: 1100, secondary_reading_out: 500)
      end
      let!(:closing_reading) do
        create(:meter_reading_event, recorded_at: Time.zone.local(2026, 7, 1, 12), property: property,
          main_reading: 1150, secondary_reading: 500)
      end

      def periods
        described_class.run!(property: property, date_range: { start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 7, 31) })
      end

      it "puts a check-out-day entry into the visitor's own stay (E5), not the empty house after it" do
        entry = create(:manual_consumption_entry, visitor: visitor_a, property: property, date: Date.new(2026, 6, 20), kwh: 33)

        result = periods
        expect(result[1][:present_visitors]).to contain_exactly(visitor_a)
        expect(result[1][:manual_entries]).to contain_exactly(entry)
        expect(result[2][:manual_entries]).to be_empty
      end

      it "puts a check-in-day entry into the visitor's own stay, not the empty house before it" do
        entry = create(:manual_consumption_entry, visitor: visitor_a, property: property, date: Date.new(2026, 6, 10), kwh: 5)

        result = periods
        expect(result[1][:manual_entries]).to contain_exactly(entry)
        expect(result[0][:manual_entries]).to be_empty
      end

      it "gives an entry by someone who wasn't staying to the later period only, so it is counted once" do
        entry = create(:manual_consumption_entry, visitor: visitor_b, property: property, date: Date.new(2026, 6, 20), kwh: 7)

        result = periods
        expect(result[1][:manual_entries]).to be_empty
        expect(result[2][:manual_entries]).to contain_exactly(entry)
      end

      it "includes an entry dated on the day of the latest reading instead of leaving it out of the report" do
        entry = create(:manual_consumption_entry, visitor: visitor_b, property: property, date: Date.new(2026, 7, 1), kwh: 4)

        expect(periods.flat_map { |p| p[:manual_entries] }).to contain_exactly(entry)
      end
    end
  end
end
