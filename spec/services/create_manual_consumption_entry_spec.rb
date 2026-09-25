# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateManualConsumptionEntry, type: :service do
  let(:property) { create(:property) }
  let(:visitor) { create(:visitor, property: property) }
  let(:user) { create(:user) }
  let(:valid_params) do
    {
      visitor: visitor,
      property: property,
      date: Date.current,
      kwh: 15.5,
      note: "EV charging",
      recorded_by_user: user
    }
  end

  describe ".run" do
    context "with valid parameters" do
      it "creates a manual consumption entry" do
        expect {
          described_class.run!(valid_params)
        }.to change(ManualConsumptionEntry, :count).by(1)
      end

      it "returns the created entry" do
        outcome = described_class.run(valid_params)

        expect(outcome).to be_valid
        expect(outcome.result).to be_a(ManualConsumptionEntry)
        expect(outcome.result).to be_persisted
      end

      it "sets all attributes correctly" do
        entry = described_class.run!(valid_params)

        expect(entry.visitor).to eq(visitor)
        expect(entry.property).to eq(property)
        expect(entry.date).to eq(Date.current)
        expect(entry.kwh).to eq(15.5)
        expect(entry.note).to eq("EV charging")
        expect(entry.recorded_by_user).to eq(user)
      end
    end

    context "with missing required fields" do
      it "fails when visitor is missing" do
        params = valid_params.except(:visitor)
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:visitor]).to be_present
      end

      it "fails when property is missing" do
        params = valid_params.except(:property)
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:property]).to be_present
      end

      it "fails when date is missing" do
        params = valid_params.except(:date)
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:date]).to be_present
      end

      it "fails when kwh is missing" do
        params = valid_params.except(:kwh)
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:kwh]).to be_present
      end

      it "fails when note is missing" do
        params = valid_params.merge(note: "")
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:note]).to be_present
      end

      it "fails when recorded_by_user is missing" do
        params = valid_params.except(:recorded_by_user)
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:recorded_by_user]).to be_present
      end
    end

    context "constraint C7: positive kWh validation" do
      it "fails when kwh is zero" do
        params = valid_params.merge(kwh: 0)
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:kwh]).to include("must be positive")
      end

      it "fails when kwh is negative" do
        params = valid_params.merge(kwh: -5.5)
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:kwh]).to include("must be positive")
      end

      it "allows very small positive values" do
        params = valid_params.merge(kwh: 0.01)
        outcome = described_class.run(params)

        expect(outcome).to be_valid
        expect(outcome.result.kwh).to eq(0.01)
      end
    end

    context "edge case E4: manual entry during empty house" do
      # This test is a placeholder for when period analysis service is implemented
      # Once we have the period analysis service, this test should:
      # 1. Set up a period with no open stays (empty house)
      # 2. Calculate the unattributed consumption for that period
      # 3. Create a manual entry within that period
      # 4. Verify the entry is deducted from the empty-house shared pool

      it "creates entry successfully during empty house period" do
        # For now, just verify the entry is created
        # TODO: Add period consumption validation when PeriodAnalysisService exists
        outcome = described_class.run(valid_params)

        expect(outcome).to be_valid
        expect(outcome.result).to be_persisted
      end
    end

    context "edge case E5: manual entry during active stay" do
      # This test is a placeholder for when period analysis service is implemented
      # Once we have the period analysis service, this test should:
      # 1. Set up a period with open stays (active visitors)
      # 2. Calculate the shared consumption for that period
      # 3. Create a manual entry within that period
      # 4. Verify the entry is deducted from the shared pool for that period

      let(:other_visitor) { create(:visitor) }

      before do
        # Create a stay to represent an active visitor during the entry date
        # This simulates edge case E5
        # TODO: Wire this to period analysis when available
      end

      it "creates entry successfully during active stay period" do
        # For now, just verify the entry is created
        # TODO: Add period consumption validation when PeriodAnalysisService exists
        outcome = described_class.run(valid_params)

        expect(outcome).to be_valid
        expect(outcome.result).to be_persisted
      end
    end

    context "constraint C8: an EV charge logged for more kWh than the house used in that period" do
      # Period 1 Jan 18:00 -> 3 Jan 10:00 measured 20 kWh on the main meter.
      let(:period_start) { Time.zone.local(2026, 1, 1, 18, 0) }
      let(:period_end) { Time.zone.local(2026, 1, 3, 10, 0) }

      before do
        create(:meter_reading_event, :check_in, property: property, recorded_at: period_start, main_reading: 1000)
        create(:meter_reading_event, :check_out, property: property, recorded_at: period_end, main_reading: 1020)
      end

      it "still saves the entry but warns, because C8 is a soft validation" do
        outcome = described_class.run(valid_params.merge(date: Date.new(2026, 1, 2), kwh: 500))

        expect(outcome).to be_valid
        expect(outcome.result).to be_persisted
        expect(outcome.consumption_warning).to include("500")
        expect(outcome.consumption_warning).to include("20")
      end

      it "stays quiet when the entry fits into the period's measured consumption" do
        outcome = described_class.run(valid_params.merge(date: Date.new(2026, 1, 2), kwh: 15))

        expect(outcome).to be_valid
        expect(outcome.consumption_warning).to be_nil
      end

      it "counts entries already logged in the period, so two small charges that together overshoot warn" do
        create(:manual_consumption_entry, visitor: visitor, property: property, date: Date.new(2026, 1, 1), kwh: 15)

        outcome = described_class.run(valid_params.merge(date: Date.new(2026, 1, 2), kwh: 10))

        expect(outcome.consumption_warning).to be_present
      end

      it "does not warn for an entry after the last reading, because that period is still open" do
        outcome = described_class.run(valid_params.merge(date: Date.new(2026, 1, 5), kwh: 500))

        expect(outcome).to be_valid
        expect(outcome.consumption_warning).to be_nil
      end
    end

    context "the visitor belongs to a different property than the entry" do
      it "refuses, so one property's pool is never billed to another property's visitor" do
        foreign_visitor = create(:visitor, property: create(:property))

        outcome = described_class.run(valid_params.merge(visitor: foreign_visitor))

        expect(outcome).not_to be_valid
        expect(outcome.errors[:visitor]).to be_present
        expect(ManualConsumptionEntry.count).to eq(0)
      end
    end

    context "with invalid visitor" do
      it "fails when visitor is wrong type" do
        params = valid_params.merge(visitor: "not a visitor")
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:visitor]).to be_present
      end
    end

    context "with invalid property" do
      it "fails when property is wrong type" do
        params = valid_params.merge(property: "not a property")
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:property]).to be_present
      end
    end

    context "with invalid date" do
      it "fails when date is wrong type" do
        params = valid_params.merge(date: "not a date")
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:date]).to be_present
      end
    end

    context "with invalid kwh" do
      it "fails when kwh is not a number" do
        params = valid_params.merge(kwh: "not a number")
        outcome = described_class.run(params)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:kwh]).to be_present
      end
    end

    context "auditing" do
      it "records the entry creation in audit log" do
        entry = described_class.run!(valid_params)

        expect(entry.audits.count).to eq(1)
        expect(entry.audits.first.action).to eq("create")
      end
    end
  end
end
