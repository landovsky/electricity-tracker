# frozen_string_literal: true

require "rails_helper"

# Tests based on the hand-calculated XLS model: "Suchá electricity test model"
# These scenarios validate the two-pool consumption algorithm:
#   - Primary pool = primary delta - secondary delta (shared among primary participants)
#   - Secondary pool = secondary delta (shared among secondary participants)
#   - Manual entries are subtracted from the relevant pool before splitting
#   - Cross-period reconciliation handles unreconciled secondary consumption
#
# Key domain concept: the secondary (garage) meter is subordinate to the primary.
# When the garage uses 6 kWh, the primary meter also advances by 6 kWh.
# Total actual consumption = primary delta.
RSpec.describe CalculateConsumption, "XLS model scenarios", type: :service do
  let(:property) { create(:property, tracking_mode: :visitors) }
  let(:primary_meter) { create(:meter, property: property, meter_type: :main, label: "Primary") }
  let(:secondary_meter) { create(:meter, property: property, meter_type: :secondary, label: "Garage") }
  let(:user) { create(:user) }

  let(:tom) { create(:visitor, name: "Tom", property: property) }
  let(:petr) { create(:visitor, name: "Petr", property: property) }
  let(:jiri) { create(:visitor, name: "Jiří", property: property) }

  # Helper: create a meter reading event with optional primary and secondary readings
  def create_event(recorded_at:, primary: nil, secondary: nil, event_type: :check_in)
    event = create(:meter_reading_event,
      recorded_at: recorded_at,
      event_type: event_type,
      recorded_by_user: user)

    if primary
      create(:meter_reading, meter_reading_event: event, meter: primary_meter, value_kwh: primary)
    end

    if secondary
      create(:meter_reading, meter_reading_event: event, meter: secondary_meter, value_kwh: secondary)
    end

    event
  end

  def run_report(start_date:, end_date:)
    CalculateConsumption.run(
      property: property,
      start_date: start_date,
      end_date: end_date
    )
  end

  def visitor_total(result, visitor)
    entry = result[:visitors].find { |v| v[:visitor] == visitor }
    entry ? entry[:total_kwh] : 0.0
  end

  # =========================================================================
  # Scenario 1: Single visitor
  # Tom checks in and out alone. Primary includes secondary consumption.
  # Primary delta = 10, secondary delta = 5.
  # Total consumption = primary delta = 10 (all Tom's).
  # =========================================================================
  context "scenario 1: single visitor" do
    it "attributes all consumption to the single visitor" do
      ci = create_event(recorded_at: "2026-01-01 12:00", primary: 10, secondary: 20)
      co = create_event(recorded_at: "2026-01-05 12:00", primary: 20, secondary: 25, event_type: :check_out)
      create(:stay, visitor: tom, property: property, check_in_event: ci, check_out_event: co)

      outcome = run_report(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 5))

      expect(outcome).to be_valid
      expect(visitor_total(outcome.result, tom)).to eq(10.0)
      expect(outcome.result[:total_consumption_kwh]).to eq(10.0)
    end
  end

  # =========================================================================
  # Scenario 2: Overlapping visitors
  # Tom checks in, then Petr checks in, then Tom leaves, then Petr leaves.
  # Period 1 (Jan 6-8):  primary delta=3, Tom alone → Tom 3
  # Period 2 (Jan 8-10): primary delta=10, Tom+Petr → 5 each
  # Period 3 (Jan 10-12): primary delta=5, Petr alone → Petr 5
  # Tom=8, Petr=10, total=18
  # =========================================================================
  context "scenario 2: overlapping visitors" do
    it "splits shared periods equally" do
      ci_tom = create_event(recorded_at: "2026-01-06 12:00", primary: 20, secondary: 25)
      ci_petr = create_event(recorded_at: "2026-01-08 12:00", primary: 23, secondary: 28)
      co_tom = create_event(recorded_at: "2026-01-10 12:00", primary: 33, secondary: 33, event_type: :check_out)
      co_petr = create_event(recorded_at: "2026-01-12 12:00", primary: 38, secondary: 35, event_type: :check_out)

      create(:stay, visitor: tom, property: property, check_in_event: ci_tom, check_out_event: co_tom)
      create(:stay, visitor: petr, property: property, check_in_event: ci_petr, check_out_event: co_petr)

      outcome = run_report(start_date: Date.new(2026, 1, 6), end_date: Date.new(2026, 1, 12))

      expect(outcome).to be_valid
      expect(visitor_total(outcome.result, tom)).to eq(8.0)
      expect(visitor_total(outcome.result, petr)).to eq(10.0)
      expect(outcome.result[:total_consumption_kwh]).to eq(18.0)
    end
  end

  # =========================================================================
  # Scenario 3: Secondary meter with cross-period reconciliation
  # Jiří uses the garage (secondary meter only). Petr uses the house.
  #
  # Period 1 (Jan 15-20): primary delta=8, secondary delta=8.
  #   Primary pool = 8-8 = 0 (no shared consumption).
  #   Secondary pool = 8 → Jiří alone → Jiří 8.
  #
  # Period 2 (Jan 20-25): primary delta=0, secondary delta=6.
  #   Jiří checked out with secondary=49 but primary unchanged (46).
  #   Secondary pool = 6 → Jiří → 6 (unreconciled: primary will catch up).
  #
  # Period 3 (Jan 25-26): primary delta=13, secondary delta=0.
  #   Primary caught up. Subtract unreconciled 6 from primary pool.
  #   Primary pool = 13-0-6(unreconciled) = 7 → Petr alone → 7.
  #
  # Jiří=14, Petr=7, total=21
  # =========================================================================
  context "scenario 3: secondary meter with reconciliation" do
    it "handles unreconciled secondary consumption across periods" do
      ci_jiri = create_event(recorded_at: "2026-01-15 12:00", primary: 38, secondary: 35)
      ci_petr = create_event(recorded_at: "2026-01-20 12:00", primary: 46, secondary: 43)
      co_jiri = create_event(recorded_at: "2026-01-25 12:00", primary: 46, secondary: 49, event_type: :check_out)
      co_petr = create_event(recorded_at: "2026-01-26 12:00", primary: 59, secondary: 49, event_type: :check_out)

      create(:stay, visitor: jiri, property: property, check_in_event: ci_jiri, check_out_event: co_jiri)
      create(:stay, visitor: petr, property: property, check_in_event: ci_petr, check_out_event: co_petr)

      outcome = run_report(start_date: Date.new(2026, 1, 15), end_date: Date.new(2026, 1, 26))

      expect(outcome).to be_valid
      expect(visitor_total(outcome.result, jiri)).to eq(14.0)
      expect(visitor_total(outcome.result, petr)).to eq(7.0)
      expect(outcome.result[:total_consumption_kwh]).to eq(21.0)
    end
  end

  # =========================================================================
  # Scenario 4: Manual consumption entry
  # Tom and Petr overlap. Tom has 33 kWh manual entry (car charging).
  #
  # Period 1 (Feb 1 Tom CI → Feb 1 Petr CI): primary delta=5, Tom alone → Tom 5
  # Period 2 (Feb 1 Petr CI → Feb 5 Tom CO): primary delta=45, Tom+Petr.
  #   Manual 33 kWh for Tom. Shared = 45-33 = 12, split 2 ways = 6 each.
  #   Tom: 6+33=39, Petr: 6
  # Period 3 (Feb 5 Tom CO → Feb 6 Petr CO): primary delta=7, Petr alone → 7
  #
  # Tom=44, Petr=13, total=57
  # =========================================================================
  context "scenario 4: manual consumption entry" do
    it "subtracts manual entry before splitting shared pool" do
      ci_tom = create_event(recorded_at: "2026-02-01 10:00", primary: 59, secondary: 49)
      ci_petr = create_event(recorded_at: "2026-02-01 14:00", primary: 64, secondary: 49)
      co_tom = create_event(recorded_at: "2026-02-05 12:00", primary: 109, secondary: 49, event_type: :check_out)
      co_petr = create_event(recorded_at: "2026-02-06 12:00", primary: 116, secondary: 49, event_type: :check_out)

      create(:stay, visitor: tom, property: property, check_in_event: ci_tom, check_out_event: co_tom)
      create(:stay, visitor: petr, property: property, check_in_event: ci_petr, check_out_event: co_petr)

      create(:manual_consumption_entry,
        visitor: tom,
        property: property,
        date: Date.new(2026, 2, 4),
        kwh: 33.0,
        note: "car charging")

      outcome = run_report(start_date: Date.new(2026, 2, 1), end_date: Date.new(2026, 2, 6))

      expect(outcome).to be_valid
      expect(visitor_total(outcome.result, tom)).to eq(44.0)
      expect(visitor_total(outcome.result, petr)).to eq(13.0)
      expect(outcome.result[:total_consumption_kwh]).to eq(57.0)
    end
  end

  # =========================================================================
  # Scenario 5: Cross-year reconciliation
  # Unreconciled secondary consumption at end of 2025 must carry over to 2026.
  # Jiří checks out Dec 30 with primary unchanged. Petr checks out Jan 2
  # with primary caught up. A 2026-only report must still subtract Jiří's
  # unreconciled kWh from Petr's allocation.
  # =========================================================================
  context "scenario 5: cross-year reconciliation" do
    it "carries unreconciled secondary across date range boundaries" do
      # Dec 25: Jiří checks in
      ci_jiri = create_event(recorded_at: "2025-12-25 12:00", primary: 100, secondary: 50)
      # Dec 27: Petr checks in
      ci_petr = create_event(recorded_at: "2025-12-27 12:00", primary: 108, secondary: 58)
      # Dec 30: Jiří checks out — primary unchanged, secondary +6
      co_jiri = create_event(recorded_at: "2025-12-30 12:00", primary: 108, secondary: 64, event_type: :check_out)
      # Jan 2: Petr checks out — primary catches up (+13 includes Jiří's 6)
      co_petr = create_event(recorded_at: "2026-01-02 12:00", primary: 121, secondary: 64, event_type: :check_out)

      create(:stay, visitor: jiri, property: property, check_in_event: ci_jiri, check_out_event: co_jiri)
      create(:stay, visitor: petr, property: property, check_in_event: ci_petr, check_out_event: co_petr)

      # Report for 2026 only — must still handle the unreconciled 6 from Dec 2025
      outcome = run_report(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31))

      expect(outcome).to be_valid
      # Petr's Jan 2 period: primary_delta=13, minus 6 unreconciled = 7
      expect(visitor_total(outcome.result, petr)).to eq(7.0)
      # Jiří's consumption was in 2025, not in this range
      expect(visitor_total(outcome.result, jiri)).to eq(0.0)
    end
  end

  # =========================================================================
  # Validation: grand totals across all scenarios
  # Tom=62, Jiří=14, Petr=30, total=106
  # =========================================================================
  context "all scenarios combined: grand totals" do
    it "produces correct per-visitor totals across all scenarios" do
      # Scenario 1: Tom alone
      s1_ci = create_event(recorded_at: "2026-01-01 12:00", primary: 10, secondary: 20)
      s1_co = create_event(recorded_at: "2026-01-05 12:00", primary: 20, secondary: 25, event_type: :check_out)
      create(:stay, visitor: tom, property: property, check_in_event: s1_ci, check_out_event: s1_co)

      # Scenario 2: Tom + Petr overlapping
      s2_ci_tom = create_event(recorded_at: "2026-01-06 12:00", primary: 20, secondary: 25)
      s2_ci_petr = create_event(recorded_at: "2026-01-08 12:00", primary: 23, secondary: 28)
      s2_co_tom = create_event(recorded_at: "2026-01-10 12:00", primary: 33, secondary: 33, event_type: :check_out)
      s2_co_petr = create_event(recorded_at: "2026-01-12 12:00", primary: 38, secondary: 35, event_type: :check_out)
      create(:stay, visitor: tom, property: property, check_in_event: s2_ci_tom, check_out_event: s2_co_tom)
      create(:stay, visitor: petr, property: property, check_in_event: s2_ci_petr, check_out_event: s2_co_petr)

      # Scenario 3: Jiří (secondary) + Petr with reconciliation
      s3_ci_jiri = create_event(recorded_at: "2026-01-15 12:00", primary: 38, secondary: 35)
      s3_ci_petr = create_event(recorded_at: "2026-01-20 12:00", primary: 46, secondary: 43)
      s3_co_jiri = create_event(recorded_at: "2026-01-25 12:00", primary: 46, secondary: 49, event_type: :check_out)
      s3_co_petr = create_event(recorded_at: "2026-01-26 12:00", primary: 59, secondary: 49, event_type: :check_out)
      create(:stay, visitor: jiri, property: property, check_in_event: s3_ci_jiri, check_out_event: s3_co_jiri)
      create(:stay, visitor: petr, property: property, check_in_event: s3_ci_petr, check_out_event: s3_co_petr)

      # Scenario 4: Tom + Petr with manual entry
      s4_ci_tom = create_event(recorded_at: "2026-02-01 10:00", primary: 59, secondary: 49)
      s4_ci_petr = create_event(recorded_at: "2026-02-01 14:00", primary: 64, secondary: 49)
      s4_co_tom = create_event(recorded_at: "2026-02-05 12:00", primary: 109, secondary: 49, event_type: :check_out)
      s4_co_petr = create_event(recorded_at: "2026-02-06 12:00", primary: 116, secondary: 49, event_type: :check_out)
      create(:stay, visitor: tom, property: property, check_in_event: s4_ci_tom, check_out_event: s4_co_tom)
      create(:stay, visitor: petr, property: property, check_in_event: s4_ci_petr, check_out_event: s4_co_petr)

      create(:manual_consumption_entry,
        visitor: tom,
        property: property,
        date: Date.new(2026, 2, 4),
        kwh: 33.0,
        note: "car charging")

      outcome = run_report(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 2, 6))

      expect(outcome).to be_valid
      result = outcome.result

      expect(visitor_total(result, tom)).to eq(62.0)
      expect(visitor_total(result, jiri)).to eq(14.0)
      expect(visitor_total(result, petr)).to eq(30.0)
      expect(result[:total_consumption_kwh]).to eq(106.0)
    end
  end
end
