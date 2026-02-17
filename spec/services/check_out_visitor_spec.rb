# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckOutVisitor, type: :service do
  let(:user) { create(:user) }
  let(:property) { create(:property) }
  let(:visitor) { create(:visitor) }
  let!(:main_meter) { create(:meter, :main, property: property) }
  let!(:secondary_meter) { create(:meter, :secondary, property: property) }

  describe ".run" do
    context "when check-out is successful (happy path)" do
      let!(:stay) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: 3.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0,
          recorded_by: user)
      end

      it "closes the stay and returns it" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0,
          secondary_meter_reading: 525.0,
          note: "Check out after visit"
        )

        expect(outcome).to be_valid
        expect(outcome.result).to eq(stay)
        expect(outcome.result.reload.status).to eq("closed")
      end

      it "creates a check-out meter reading event" do
        expect do
          described_class.run(
            visitor: visitor,
            property: property,
            recorded_at: Time.current,
            recorded_by_user: user,
            main_meter_reading: 1050.0,
            secondary_meter_reading: 525.0
          )
        end.to change(MeterReadingEvent, :count).by(1)

        event = MeterReadingEvent.last
        expect(event.event_type).to eq("check_out")
        expect(event.recorded_by_user).to eq(user)
      end

      it "creates meter readings for main and secondary meters" do
        expect do
          described_class.run(
            visitor: visitor,
            property: property,
            recorded_at: Time.current,
            recorded_by_user: user,
            main_meter_reading: 1050.0,
            secondary_meter_reading: 525.0
          )
        end.to change(MeterReading, :count).by(2)

        check_out_event = MeterReadingEvent.last
        main_reading = check_out_event.meter_readings.find_by(meter: main_meter)
        secondary_reading = check_out_event.meter_readings.find_by(meter: secondary_meter)

        expect(main_reading.value_kwh).to eq(1050.0)
        expect(secondary_reading.value_kwh).to eq(525.0)
      end

      it "associates the check-out event with the stay" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0,
          secondary_meter_reading: 525.0
        )

        stay.reload
        expect(stay.check_out_event).to be_present
        expect(stay.check_out_event.event_type).to eq("check_out")
      end

      it "includes the note in the meter reading event" do
        described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0,
          note: "Early departure"
        )

        event = MeterReadingEvent.last
        expect(event.note).to eq("Early departure")
      end
    end

    context "when providing stay instead of visitor" do
      let!(:stay) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: 2.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0)
      end

      it "uses the provided stay" do
        outcome = described_class.run(
          stay: stay,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0
        )

        expect(outcome).to be_valid
        expect(outcome.result).to eq(stay)
        expect(stay.reload.status).to eq("closed")
      end
    end

    context "Edge case E3: same-day check-in and check-out" do
      let!(:stay) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: Time.current - 2.hours,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0)
      end

      it "allows check-out on the same day as check-in" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1000.0, # Same reading - 0 kWh delta is fine
          secondary_meter_reading: 500.0
        )

        expect(outcome).to be_valid
        expect(outcome.result.reload.status).to eq("closed")
      end

      it "allows 0 kWh consumption (same meter readings)" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1000.0,
          secondary_meter_reading: 500.0
        )

        expect(outcome).to be_valid
        check_out_event = MeterReadingEvent.last
        main_reading = check_out_event.meter_readings.find_by(meter: main_meter)
        expect(main_reading.value_kwh).to eq(1000.0)
      end
    end

    context "Edge case E8: secondary meter not read" do
      let!(:stay) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: 2.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0)
      end

      it "allows check-out without secondary meter reading" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0
          # secondary_meter_reading intentionally omitted
        )

        expect(outcome).to be_valid
      end

      it "defaults to last known secondary meter reading" do
        described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0
        )

        check_out_event = MeterReadingEvent.last
        secondary_reading = check_out_event.meter_readings.find_by(meter: secondary_meter)

        expect(secondary_reading).to be_present
        expect(secondary_reading.value_kwh).to eq(500.0) # Same as check-in
      end

      it "creates only main meter reading when secondary meter doesn't exist" do
        secondary_meter.discard

        expect do
          described_class.run(
            visitor: visitor,
            property: property,
            recorded_at: Time.current,
            recorded_by_user: user,
            main_meter_reading: 1050.0
          )
        end.to change(MeterReading, :count).by(1)

        check_out_event = MeterReadingEvent.last
        expect(check_out_event.meter_readings.count).to eq(1)
        expect(check_out_event.meter_readings.first.meter).to eq(main_meter)
      end
    end

    context "Constraint C1: meter readings are monotonically non-decreasing" do
      let!(:previous_stay) do
        create(:stay, :closed,
          visitor: visitor,
          property: property,
          check_in_at: 5.days.ago,
          check_out_at: 4.days.ago,
          main_reading_in: 900.0,
          main_reading_out: 950.0,
          secondary_reading_in: 450.0,
          secondary_reading_out: 475.0)
      end

      let!(:current_stay) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: 2.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0)
      end

      it "rejects main meter reading less than previous reading" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 950.0, # Less than check-in reading of 1000.0
          secondary_meter_reading: 525.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include(
          match(/Main.*950\.0.*1000\.0/)
        )
      end

      it "rejects secondary meter reading less than previous reading" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0,
          secondary_meter_reading: 475.0 # Less than check-in reading of 500.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include(
          match(/Secondary.*475\.0.*500\.0/)
        )
      end

      it "allows meter reading equal to previous reading" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1000.0, # Equal to check-in
          secondary_meter_reading: 500.0
        )

        expect(outcome).to be_valid
      end
    end

    context "Constraint C3: check-out reading >= check-in reading" do
      let!(:stay) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: 2.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0)
      end

      it "rejects main meter reading less than check-in reading" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 950.0, # Less than check-in
          secondary_meter_reading: 525.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include(
          match(/Main.*950\.0.*1000\.0/)
        )
      end

      it "rejects secondary meter reading less than check-in reading" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0,
          secondary_meter_reading: 450.0 # Less than check-in
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include(
          match(/Secondary.*450\.0.*500\.0/)
        )
      end

      it "allows check-out reading equal to check-in reading" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1000.0,
          secondary_meter_reading: 500.0
        )

        expect(outcome).to be_valid
      end

      it "allows check-out reading greater than check-in reading" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1100.0,
          secondary_meter_reading: 550.0
        )

        expect(outcome).to be_valid
      end
    end

    context "when visitor has no open stay" do
      it "returns error for visitor without open stay" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include(
          match(/Návštěvník .* nemá otevřený pobyt/)
        )
      end
    end

    context "when stay is already closed" do
      let!(:stay) do
        create(:stay, :closed,
          visitor: visitor,
          property: property,
          check_in_at: 3.days.ago,
          check_out_at: 1.day.ago,
          main_reading_in: 1000.0,
          main_reading_out: 1050.0)
      end

      it "returns error when trying to check out already closed stay" do
        outcome = described_class.run(
          stay: stay,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1100.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include("Pobyt je již uzavřen")
      end
    end

    context "when neither visitor nor stay is provided" do
      it "returns validation error" do
        outcome = described_class.run(
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include("Musí být zadán buď návštěvník, nebo pobyt")
      end
    end

    context "when main meter is missing" do
      before { main_meter.discard }

      let!(:stay) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: 2.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0)
      end

      it "returns error when main meter not found" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include("Hlavní měřič pro nemovitost nebyl nalezen")
      end
    end

    context "transaction rollback" do
      let!(:stay) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: 2.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0)
      end

      it "rolls back all changes when meter reading validation fails" do
        expect do
          described_class.run(
            visitor: visitor,
            property: property,
            recorded_at: Time.current,
            recorded_by_user: user,
            main_meter_reading: 950.0 # Invalid - less than check-in
          )
        end.not_to change(MeterReadingEvent, :count)

        stay.reload
        expect(stay.status).to eq("open")
        expect(stay.check_out_event).to be_nil
      end

      it "rolls back when stay update fails" do
        allow_any_instance_of(Stay).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        expect do
          described_class.run(
            visitor: visitor,
            property: property,
            recorded_at: Time.current,
            recorded_by_user: user,
            main_meter_reading: 1050.0
          )
        end.not_to change(MeterReadingEvent, :count)
      end
    end

    context "with multiple visitors having stays" do
      let(:visitor2) { create(:visitor) }
      let!(:stay1) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: 3.days.ago,
          main_reading_in: 1000.0,
          secondary_reading_in: 500.0)
      end

      let!(:stay2) do
        create(:stay, :open,
          visitor: visitor2,
          property: property,
          check_in_at: 2.days.ago,
          main_reading_in: 1020.0,
          secondary_reading_in: 510.0)
      end

      it "checks out only the specified visitor" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0,
          secondary_meter_reading: 525.0
        )

        expect(outcome).to be_valid
        expect(stay1.reload.status).to eq("closed")
        expect(stay2.reload.status).to eq("open")
      end

      it "respects monotonic constraint across different visitors" do
        # Check out visitor2 first
        described_class.run(
          visitor: visitor2,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0
        )

        # Try to check out visitor with lower reading - should fail
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current + 1.hour,
          recorded_by_user: user,
          main_meter_reading: 1040.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include(
          match(/musí být větší nebo roven předchozímu odečtu/)
        )
      end
    end

    context "required validations" do
      let!(:stay) do
        create(:stay, :open,
          visitor: visitor,
          property: property,
          check_in_at: 2.days.ago,
          main_reading_in: 1000.0)
      end

      it "requires property" do
        outcome = described_class.run(
          visitor: visitor,
          recorded_at: Time.current,
          recorded_by_user: user,
          main_meter_reading: 1050.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:property]).to be_present
      end

      it "requires recorded_by_user" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          main_meter_reading: 1050.0
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:recorded_by_user]).to be_present
      end

      it "requires main_meter_reading" do
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_at: Time.current,
          recorded_by_user: user
        )

        expect(outcome).not_to be_valid
        expect(outcome.errors[:main_meter_reading]).to be_present
      end

      it "defaults recorded_at to current time" do
        before_time = Time.current
        outcome = described_class.run(
          visitor: visitor,
          property: property,
          recorded_by_user: user,
          main_meter_reading: 1050.0
        )
        after_time = Time.current

        expect(outcome).to be_valid
        event = MeterReadingEvent.last
        expect(event.recorded_at).to be_between(before_time, after_time)
      end
    end
  end
end
