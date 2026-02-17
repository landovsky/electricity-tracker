require 'rails_helper'

RSpec.describe MeterReadingEvent, type: :model do
  describe "associations" do
    it { should belong_to(:recorded_by_user).class_name("User").optional }
    it { should have_many(:meter_readings).dependent(:destroy) }
    it { should have_one(:stay_as_check_in).class_name("Stay").with_foreign_key(:check_in_event_id).dependent(:nullify) }
    it { should have_one(:stay_as_check_out).class_name("Stay").with_foreign_key(:check_out_event_id).dependent(:nullify) }
  end

  describe "validations" do
    it { should validate_presence_of(:recorded_at) }
    it { should validate_presence_of(:event_type) }
  end

  describe "enums" do
    it { should define_enum_for(:event_type).backed_by_column_of_type(:string).with_values(check_in: "check_in", check_out: "check_out") }
  end

  describe "scopes" do
    let!(:event1) { MeterReadingEvent.create!(recorded_at: 2.days.ago, event_type: "check_in") }
    let!(:event2) { MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_out") }
    let!(:event3) { MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_in") }

    describe ".recent" do
      it "returns events in reverse chronological order" do
        expect(MeterReadingEvent.recent.pluck(:id)).to eq([ event3.id, event2.id, event1.id ])
      end
    end

    describe ".chronological" do
      it "returns events in chronological order" do
        expect(MeterReadingEvent.chronological.pluck(:id)).to eq([ event1.id, event2.id, event3.id ])
      end
    end
  end

  describe "audit trail" do
    it "is audited" do
      expect(MeterReadingEvent.new).to respond_to(:audits)
    end
  end

  describe "soft deletes" do
    it "includes Discard::Model" do
      expect(MeterReadingEvent.included_modules).to include(Discard::Model)
    end
  end

  describe "C6: chronological consistency" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:meter) { Meter.create!(property: property, meter_type: "main", label: "Main", unit: "kWh") }

    before do
      event1 = MeterReadingEvent.create!(recorded_at: 2.days.ago, event_type: "check_in")
      event1.meter_readings.create!(meter: meter, value_kwh: 100)
    end

    it "allows events with timestamps after previous events" do
      event = MeterReadingEvent.new(recorded_at: 1.day.ago, event_type: "check_out")
      event.meter_readings.build(meter: meter, value_kwh: 150)
      expect(event).to be_valid
    end

    it "allows events with timestamps equal to previous events" do
      event = MeterReadingEvent.new(recorded_at: 2.days.ago, event_type: "check_out")
      event.meter_readings.build(meter: meter, value_kwh: 150)
      expect(event).to be_valid
    end

    it "prevents events with timestamps before previous events" do
      event = MeterReadingEvent.new(recorded_at: 3.days.ago, event_type: "check_in")
      event.meter_readings.build(meter: meter, value_kwh: 50)
      expect(event).not_to be_valid
      expect(event.errors[:recorded_at]).to include(match(/musí být po předchozí události/))
    end
  end

  describe "C4: main meter reading required" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:main_meter) { Meter.create!(property: property, meter_type: "main", label: "Main", unit: "kWh") }
    let(:secondary_meter) { Meter.create!(property: property, meter_type: "secondary", label: "Secondary", unit: "kWh") }

    it "is valid when main meter reading is present" do
      event = MeterReadingEvent.new(recorded_at: Time.current, event_type: "check_in")
      event.meter_readings.build(meter: main_meter, value_kwh: 100)
      expect(event).to be_valid
    end

    it "is invalid when only secondary meter reading is present" do
      event = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_in")
      event.meter_readings.create!(meter: secondary_meter, value_kwh: 50)
      event.reload
      expect(event).not_to be_valid
      expect(event.errors[:base]).to include(I18n.t("activerecord.errors.models.meter_reading_event.attributes.base.main_meter_required"))
    end

    it "is valid when both main and secondary meter readings are present" do
      event = MeterReadingEvent.new(recorded_at: Time.current, event_type: "check_in")
      event.meter_readings.build(meter: main_meter, value_kwh: 100)
      event.meter_readings.build(meter: secondary_meter, value_kwh: 50)
      expect(event).to be_valid
    end
  end
end
