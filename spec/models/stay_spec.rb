require 'rails_helper'

RSpec.describe Stay, type: :model do
  describe "associations" do
    it { should belong_to(:visitor) }
    it { should belong_to(:property) }
    it { should belong_to(:check_in_event).class_name("MeterReadingEvent").optional }
    it { should belong_to(:check_out_event).class_name("MeterReadingEvent").optional }
  end

  describe "validations" do
    it { should validate_presence_of(:visitor_id) }
    it { should validate_presence_of(:property_id) }
  end

  describe "scopes" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor1) { Visitor.create!(name: "Test Visitor 1", status: "active") }
    let(:visitor2) { Visitor.create!(name: "Test Visitor 2", status: "active") }

    before do
      check_in1 = MeterReadingEvent.create!(recorded_at: 2.days.ago, event_type: "check_in")
      check_in2 = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
      check_out2 = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")

      Stay.create!(visitor: visitor1, property: property, check_in_event: check_in1)
      Stay.create!(visitor: visitor2, property: property, check_in_event: check_in2, check_out_event: check_out2)
    end

    describe ".open" do
      it "returns only open stays" do
        expect(Stay.open.count).to eq(1)
        expect(Stay.open.first.check_out_event_id).to be_nil
      end
    end

    describe ".closed" do
      it "returns only closed stays" do
        expect(Stay.closed.count).to eq(1)
        expect(Stay.closed.first.check_out_event_id).not_to be_nil
      end
    end
  end

  describe "audit trail" do
    it "is audited" do
      expect(Stay.new).to respond_to(:audits)
    end
  end

  describe "soft deletes" do
    it "includes Discard::Model" do
      expect(Stay.included_modules).to include(Discard::Model)
    end
  end

  describe "#status" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }

    it "returns 'open' when check_out_event_id is nil" do
      check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
      stay = Stay.create!(visitor: visitor, property: property, check_in_event: check_in)
      expect(stay.status).to eq("open")
    end

    it "returns 'closed' when check_out_event_id is present" do
      check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
      check_out = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
      stay = Stay.create!(visitor: visitor, property: property, check_in_event: check_in, check_out_event: check_out)
      expect(stay.status).to eq("closed")
    end
  end

  describe "#open?" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }

    it "returns true when stay is open" do
      check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
      stay = Stay.create!(visitor: visitor, property: property, check_in_event: check_in)
      expect(stay.open?).to be true
    end

    it "returns false when stay is closed" do
      check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
      check_out = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
      stay = Stay.create!(visitor: visitor, property: property, check_in_event: check_in, check_out_event: check_out)
      expect(stay.open?).to be false
    end
  end

  describe "#closed?" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }

    it "returns false when stay is open" do
      check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
      stay = Stay.create!(visitor: visitor, property: property, check_in_event: check_in)
      expect(stay.closed?).to be false
    end

    it "returns true when stay is closed" do
      check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
      check_out = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
      stay = Stay.create!(visitor: visitor, property: property, check_in_event: check_in, check_out_event: check_out)
      expect(stay.closed?).to be true
    end
  end

  describe "C2: visitor can have at most one open stay" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }

    context "when visitor has no open stays" do
      it "allows creating an open stay" do
        check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        stay = Stay.new(visitor: visitor, property: property, check_in_event: check_in)
        expect(stay).to be_valid
      end
    end

    context "when visitor has a closed stay" do
      before do
        check_in = MeterReadingEvent.create!(recorded_at: 2.days.ago, event_type: "check_in")
        check_out = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_out")
        Stay.create!(visitor: visitor, property: property, check_in_event: check_in, check_out_event: check_out)
      end

      it "allows creating another open stay" do
        check_in2 = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_in")
        stay = Stay.new(visitor: visitor, property: property, check_in_event: check_in2)
        expect(stay).to be_valid
      end
    end

    context "when visitor has an open stay" do
      before do
        check_in1 = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        Stay.create!(visitor: visitor, property: property, check_in_event: check_in1)
      end

      it "prevents creating another open stay" do
        check_in2 = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_in")
        stay = Stay.new(visitor: visitor, property: property, check_in_event: check_in2)
        expect(stay).not_to be_valid
        expect(stay.errors[:base]).to include(I18n.t("activerecord.errors.models.stay.attributes.base.visitor_open_stay"))
      end

      it "allows the existing open stay to be updated" do
        existing_stay = Stay.first
        existing_stay.note = "Updated note"
        expect(existing_stay).to be_valid
      end
    end

    context "when visitor has a soft-deleted open stay" do
      before do
        check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        stay = Stay.create!(visitor: visitor, property: property, check_in_event: check_in)
        stay.discard
      end

      it "allows creating a new open stay" do
        check_in2 = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_in")
        stay = Stay.new(visitor: visitor, property: property, check_in_event: check_in2)
        expect(stay).to be_valid
      end
    end
  end

  describe "C3: check-out reading >= check-in reading" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }
    let(:main_meter) { Meter.create!(property: property, meter_type: "main", label: "Main", unit: "kWh") }
    let(:secondary_meter) { Meter.create!(property: property, meter_type: "secondary", label: "Secondary", unit: "kWh") }

    context "when check-out readings are greater than check-in readings" do
      it "is valid" do
        check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        check_in.meter_readings.create!(meter: main_meter, value_kwh: 100)
        check_in.meter_readings.create!(meter: secondary_meter, value_kwh: 50)

        check_out = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
        check_out.meter_readings.create!(meter: main_meter, value_kwh: 150)
        check_out.meter_readings.create!(meter: secondary_meter, value_kwh: 70)

        stay = Stay.new(visitor: visitor, property: property, check_in_event: check_in, check_out_event: check_out)
        expect(stay).to be_valid
      end
    end

    context "when check-out readings are equal to check-in readings" do
      it "is valid (zero consumption)" do
        check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        check_in.meter_readings.create!(meter: main_meter, value_kwh: 100)

        check_out = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
        check_out.meter_readings.create!(meter: main_meter, value_kwh: 100)

        stay = Stay.new(visitor: visitor, property: property, check_in_event: check_in, check_out_event: check_out)
        expect(stay).to be_valid
      end
    end

    context "when check-out reading is less than check-in reading" do
      it "is invalid" do
        check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        check_in.meter_readings.create!(meter: main_meter, value_kwh: 100)

        check_out = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
        # Use save(validate: false) to bypass C1 validation and test C3 validation on Stay
        reading = check_out.meter_readings.new(meter: main_meter, value_kwh: 80)
        reading.save(validate: false)

        stay = Stay.new(visitor: visitor, property: property, check_in_event: check_in, check_out_event: check_out)
        expect(stay).not_to be_valid
        expect(stay.errors[:base]).to include(match(/check-out reading for Main.*must be >= check-in reading/))
      end
    end

    context "when only one meter has readings at both events" do
      it "validates only the meter with both readings" do
        check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        check_in.meter_readings.create!(meter: main_meter, value_kwh: 100)
        check_in.meter_readings.create!(meter: secondary_meter, value_kwh: 50)

        check_out = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
        check_out.meter_readings.create!(meter: main_meter, value_kwh: 150)
        # No secondary meter reading at check-out

        stay = Stay.new(visitor: visitor, property: property, check_in_event: check_in, check_out_event: check_out)
        expect(stay).to be_valid
      end
    end

    context "when stay has no check-out event (open stay)" do
      it "does not validate check-out readings" do
        check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        check_in.meter_readings.create!(meter: main_meter, value_kwh: 100)

        stay = Stay.new(visitor: visitor, property: property, check_in_event: check_in)
        expect(stay).to be_valid
      end
    end
  end

  describe "edge case: multiple overlapping stays (E1)" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor1) { Visitor.create!(name: "Visitor 1", status: "active") }
    let(:visitor2) { Visitor.create!(name: "Visitor 2", status: "active") }
    let(:visitor3) { Visitor.create!(name: "Visitor 3", status: "active") }

    it "allows multiple different visitors to have overlapping stays" do
      check_in1 = MeterReadingEvent.create!(recorded_at: 3.days.ago, event_type: "check_in")
      check_in2 = MeterReadingEvent.create!(recorded_at: 2.days.ago, event_type: "check_in")
      check_in3 = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")

      stay1 = Stay.create!(visitor: visitor1, property: property, check_in_event: check_in1)
      stay2 = Stay.create!(visitor: visitor2, property: property, check_in_event: check_in2)
      stay3 = Stay.create!(visitor: visitor3, property: property, check_in_event: check_in3)

      expect(stay1).to be_valid
      expect(stay2).to be_valid
      expect(stay3).to be_valid
      expect(Stay.open.count).to eq(3)
    end
  end
end
