# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckInVisitor, type: :service do
  include ActiveSupport::Testing::TimeHelpers
  let(:property) { create(:property) }
  let(:main_meter) { create(:meter, :main, property: property) }
  let(:secondary_meter) { create(:meter, :secondary, property: property) }
  let(:visitor) { create(:visitor) }
  let(:user) { create(:user) }

  # Default parameters for a successful check-in
  let(:valid_params) do
    {
      visitor: visitor,
      property: property,
      recorded_by_user: user,
      recorded_at: Time.current,
      main_meter_reading: 1000.0,
      secondary_meter_reading: 500.0,
      note: "Arrived for the weekend"
    }
  end

  before do
    # Ensure meters exist
    main_meter
    secondary_meter
  end

  describe "happy path - successful check-in" do
    it "creates a stay with check-in event and meter readings" do
      outcome = described_class.run(valid_params)

      expect(outcome).to be_valid
      expect(outcome.result).to be_a(Stay)

      stay = outcome.result
      expect(stay).to be_persisted
      expect(stay.visitor).to eq(visitor)
      expect(stay.property).to eq(property)
      expect(stay.status).to eq("open")
      expect(stay.check_in_event).to be_present
      expect(stay.check_out_event).to be_nil
    end

    it "creates a meter reading event with correct attributes" do
      outcome = described_class.run(valid_params)
      event = outcome.result.check_in_event

      expect(event.event_type).to eq("check_in")
      expect(event.recorded_at).to be_within(1.second).of(valid_params[:recorded_at])
      expect(event.recorded_by_user).to eq(user)
      expect(event.note).to eq("Arrived for the weekend")
    end

    it "creates meter readings for both meters" do
      outcome = described_class.run(valid_params)
      event = outcome.result.check_in_event

      expect(event.meter_readings.count).to eq(2)

      main_reading = event.meter_readings.find_by(meter: main_meter)
      expect(main_reading.value_kwh).to eq(1000.0)

      secondary_reading = event.meter_readings.find_by(meter: secondary_meter)
      expect(secondary_reading.value_kwh).to eq(500.0)
    end

    it "uses default recorded_at when not provided" do
      params = valid_params.except(:recorded_at)
      travel_to Time.current do
        outcome = described_class.run(params)
        expect(outcome.result.check_in_event.recorded_at).to be_within(1.second).of(Time.current)
      end
    end

    it "allows nil note" do
      params = valid_params.merge(note: nil)
      outcome = described_class.run(params)

      expect(outcome).to be_valid
      expect(outcome.result.note).to be_nil
    end
  end

  describe "E2: first check-in (no previous readings)" do
    it "succeeds with first-ever readings" do
      # No previous readings exist
      expect(MeterReading.count).to eq(0)

      outcome = described_class.run(valid_params)

      expect(outcome).to be_valid
      expect(outcome.result).to be_persisted
    end

    it "allows zero as first reading" do
      params = valid_params.merge(
        main_meter_reading: 0.0,
        secondary_meter_reading: 0.0
      )

      outcome = described_class.run(params)

      expect(outcome).to be_valid
      expect(outcome.result.check_in_event.meter_readings.find_by(meter: main_meter).value_kwh).to eq(0.0)
    end
  end

  describe "E7: forgotten reading (validation error)" do
    it "fails when main meter reading is missing" do
      params = valid_params.except(:main_meter_reading)

      outcome = described_class.run(params)

      expect(outcome).not_to be_valid
      expect(outcome.errors[:main_meter_reading]).to be_present
    end

    it "fails when main meter reading is nil" do
      params = valid_params.merge(main_meter_reading: nil)

      outcome = described_class.run(params)

      expect(outcome).not_to be_valid
    end
  end

  describe "E8: missing secondary reading (uses default)" do
    context "when there is a previous secondary reading" do
      before do
        # Create a previous event with secondary reading
        previous_event = create(:meter_reading_event,
          event_type: :check_in,
          recorded_at: 1.day.ago,
          recorded_by_user: user
        )
        create(:meter_reading,
          meter_reading_event: previous_event,
          meter: main_meter,
          value_kwh: 900.0
        )
        create(:meter_reading,
          meter_reading_event: previous_event,
          meter: secondary_meter,
          value_kwh: 450.0
        )
      end

      it "uses the last known secondary reading when not provided" do
        params = valid_params.merge(
          main_meter_reading: 1000.0,
          secondary_meter_reading: nil
        )

        outcome = described_class.run(params)

        expect(outcome).to be_valid
        secondary_reading = outcome.result.check_in_event.meter_readings.find_by(meter: secondary_meter)
        expect(secondary_reading.value_kwh).to eq(450.0)
      end
    end

    context "when there is no previous secondary reading" do
      it "does not create a secondary reading" do
        params = valid_params.merge(secondary_meter_reading: nil)

        outcome = described_class.run(params)

        expect(outcome).to be_valid
        expect(outcome.result.check_in_event.meter_readings.where(meter: secondary_meter).count).to eq(0)
      end
    end

    context "when secondary meter does not exist" do
      before do
        secondary_meter.discard
      end

      it "succeeds with only main meter reading" do
        params = valid_params.merge(secondary_meter_reading: nil)

        outcome = described_class.run(params)

        expect(outcome).to be_valid
        expect(outcome.result.check_in_event.meter_readings.count).to eq(1)
        expect(outcome.result.check_in_event.meter_readings.first.meter).to eq(main_meter)
      end
    end
  end

  describe "C1: meter reading goes down (validation error)" do
    before do
      # Create a previous event with higher readings
      previous_event = create(:meter_reading_event,
        event_type: :check_in,
        recorded_at: 1.day.ago,
        recorded_by_user: user
      )
      create(:meter_reading,
        meter_reading_event: previous_event,
        meter: main_meter,
        value_kwh: 1000.0
      )
      create(:meter_reading,
        meter_reading_event: previous_event,
        meter: secondary_meter,
        value_kwh: 500.0
      )
    end

    it "fails when main meter reading decreases" do
      params = valid_params.merge(main_meter_reading: 900.0)

      outcome = described_class.run(params)

      expect(outcome).not_to be_valid
      expect(outcome.errors[:base].first).to include("must be greater than or equal to previous reading")
    end

    it "fails when secondary meter reading decreases" do
      params = valid_params.merge(
        main_meter_reading: 1100.0,
        secondary_meter_reading: 400.0
      )

      outcome = described_class.run(params)

      expect(outcome).not_to be_valid
      expect(outcome.errors[:base].first).to include("must be greater than or equal to previous reading")
    end

    it "succeeds when readings are equal (no consumption)" do
      params = valid_params.merge(
        main_meter_reading: 1000.0,
        secondary_meter_reading: 500.0
      )

      outcome = described_class.run(params)

      expect(outcome).to be_valid
    end

    it "succeeds when readings increase" do
      params = valid_params.merge(
        main_meter_reading: 1100.0,
        secondary_meter_reading: 550.0
      )

      outcome = described_class.run(params)

      expect(outcome).to be_valid
    end
  end

  describe "C2: visitor already has open stay (validation error)" do
    before do
      # Create an open stay for the visitor
      create(:stay, :open,
        visitor: visitor,
        property: property,
        check_in_at: 2.days.ago,
        main_reading_in: 900.0,
        secondary_reading_in: 450.0,
        recorded_by: user
      )
    end

    it "fails when visitor already has an open stay" do
      outcome = described_class.run(valid_params)

      expect(outcome).not_to be_valid
      expect(outcome.errors[:visitor].first).to include("má otevřený pobyt")
    end

    it "allows check-in after previous stay is closed" do
      # Close the existing stay
      visitor.stays.open.first.update!(
        check_out_event: create(:meter_reading_event,
          event_type: :check_out,
          recorded_at: 1.day.ago,
          recorded_by_user: user,
          property: property,
          main_reading: 950.0,
          secondary_reading: 475.0
        )
      )

      outcome = described_class.run(valid_params)

      expect(outcome).to be_valid
    end
  end

  describe "C4: main meter required" do
    it "fails when main meter does not exist" do
      main_meter.discard

      outcome = described_class.run(valid_params)

      expect(outcome).not_to be_valid
      expect(outcome.errors[:base].first).to include("Couldn't find Meter")
    end
  end

  describe "C6: chronological consistency" do
    before do
      # Create a previous event
      previous_event = create(:meter_reading_event,
        event_type: :check_in,
        recorded_at: 1.day.ago,
        recorded_by_user: user
      )
      create(:meter_reading,
        meter_reading_event: previous_event,
        meter: main_meter,
        value_kwh: 900.0
      )
    end

    it "fails when recorded_at is before the previous event" do
      params = valid_params.merge(recorded_at: 2.days.ago)

      outcome = described_class.run(params)

      expect(outcome).not_to be_valid
      expect(outcome.errors[:recorded_at].first).to include("must be after previous event")
    end

    it "succeeds when recorded_at is after the previous event" do
      params = valid_params.merge(recorded_at: Time.current)

      outcome = described_class.run(params)

      expect(outcome).to be_valid
    end

    it "succeeds when recorded_at equals the previous event (concurrent check-in/check-out)" do
      params = valid_params.merge(recorded_at: 1.day.ago)

      outcome = described_class.run(params)

      expect(outcome).to be_valid
    end
  end

  describe "transaction rollback on failure" do
    it "does not create any records when meter reading validation fails" do
      # Create a previous reading
      previous_event = create(:meter_reading_event,
        event_type: :check_in,
        recorded_at: 1.day.ago,
        recorded_by_user: user
      )
      create(:meter_reading,
        meter_reading_event: previous_event,
        meter: main_meter,
        value_kwh: 1000.0
      )

      expect {
        described_class.run(valid_params.merge(main_meter_reading: 900.0))
      }.not_to change { MeterReadingEvent.count }

      expect(Stay.count).to eq(0)
      expect(MeterReading.count).to eq(1) # Only the previous reading
    end

    it "does not create any records when stay validation fails" do
      # Create an open stay
      create(:stay, :open,
        visitor: visitor,
        property: property,
        check_in_at: 2.days.ago,
        main_reading_in: 900.0,
        recorded_by: user
      )

      expect {
        described_class.run(valid_params)
      }.not_to change { MeterReadingEvent.count }
    end
  end

  describe "input validation" do
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

    it "fails when recorded_by_user is missing" do
      params = valid_params.except(:recorded_by_user)

      outcome = described_class.run(params)

      expect(outcome).not_to be_valid
      expect(outcome.errors[:recorded_by_user]).to be_present
    end

    it "fails when visitor is not a Visitor object" do
      params = valid_params.merge(visitor: "not a visitor")

      outcome = described_class.run(params)

      expect(outcome).not_to be_valid
    end
  end

  describe "edge cases" do
    it "handles large meter reading values" do
      params = valid_params.merge(
        main_meter_reading: 999_999.99,
        secondary_meter_reading: 888_888.88
      )

      outcome = described_class.run(params)

      expect(outcome).to be_valid
      expect(outcome.result.check_in_event.meter_readings.find_by(meter: main_meter).value_kwh).to eq(999_999.99)
    end

    it "handles multiple decimal places" do
      params = valid_params.merge(
        main_meter_reading: 1000.123,
        secondary_meter_reading: 500.456
      )

      outcome = described_class.run(params)

      expect(outcome).to be_valid
    end

    it "allows archived visitors to check in" do
      visitor.update!(status: :archived)

      outcome = described_class.run(valid_params)

      expect(outcome).to be_valid
    end
  end

  describe "different visitors can have simultaneous open stays" do
    let(:visitor2) { create(:visitor) }

    before do
      # Create an open stay for visitor1
      create(:stay, :open,
        visitor: visitor,
        property: property,
        check_in_at: 2.days.ago,
        main_reading_in: 900.0,
        recorded_by: user
      )
    end

    it "allows different visitors to have overlapping stays" do
      params = valid_params.merge(
        visitor: visitor2,
        main_meter_reading: 950.0
      )

      outcome = described_class.run(params)

      expect(outcome).to be_valid
      expect(Stay.open.count).to eq(2)
    end
  end
end
