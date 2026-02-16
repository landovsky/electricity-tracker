# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateManualConsumptionEntry, type: :service do
  let(:visitor) { create(:visitor) }
  let(:property) { create(:property) }
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

    context "constraint C8: period consumption warning (soft validation)" do
      # This test is a placeholder for when period analysis service is implemented
      # C8 should add a warning (not a blocking error) when the manual entry kWh
      # exceeds the unattributed consumption for the enclosing period.
      #
      # Once we have the period analysis service, this test should:
      # 1. Set up a period with known total consumption (e.g., 100 kWh)
      # 2. Create manual entries or stays that consume most of it (e.g., 95 kWh)
      # 3. Attempt to create a manual entry for 10 kWh
      # 4. Verify a warning is added to errors[:consumption_warning]
      # 5. Verify the entry is still created (soft validation)

      it "adds a warning when exceeding period consumption (placeholder)" do
        # TODO: Implement when PeriodAnalysisService is available
        # For now, verify that the service doesn't block on this
        params = valid_params.merge(kwh: 1000) # Unrealistically high value
        outcome = described_class.run(params)

        expect(outcome).to be_valid
        expect(outcome.result).to be_persisted
        # TODO: Once implemented, verify:
        # expect(outcome.errors[:consumption_warning]).to be_present
      end

      it "does not add warning when within period consumption (placeholder)" do
        # TODO: Implement when PeriodAnalysisService is available
        outcome = described_class.run(valid_params)

        expect(outcome).to be_valid
        expect(outcome.result).to be_persisted
        # TODO: Once implemented, verify:
        # expect(outcome.errors[:consumption_warning]).to be_empty
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
