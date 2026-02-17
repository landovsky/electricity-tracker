require 'rails_helper'

RSpec.describe MeterReading, type: :model do
  describe "associations" do
    it { should belong_to(:meter_reading_event) }
    it { should belong_to(:meter) }
  end

  describe "validations" do
    it { should validate_presence_of(:value_kwh) }
    it { should validate_numericality_of(:value_kwh).is_greater_than_or_equal_to(0) }
  end

  describe "soft deletes" do
    it "includes Discard::Model" do
      expect(MeterReading.included_modules).to include(Discard::Model)
    end
  end

  describe "C1: monotonically non-decreasing readings" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:meter) { Meter.create!(property: property, meter_type: "main", label: "Main", unit: "kWh") }

    context "when it's the first reading for a meter" do
      it "is valid" do
        event = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_in")
        reading = event.meter_readings.build(meter: meter, value_kwh: 100)
        expect(reading).to be_valid
      end
    end

    context "when value is greater than previous reading" do
      before do
        event1 = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        event1.meter_readings.create!(meter: meter, value_kwh: 100)
      end

      it "is valid" do
        event2 = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
        reading = event2.meter_readings.build(meter: meter, value_kwh: 150)
        expect(reading).to be_valid
      end
    end

    context "when value is equal to previous reading" do
      before do
        event1 = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        event1.meter_readings.create!(meter: meter, value_kwh: 100)
      end

      it "is valid (no consumption between readings)" do
        event2 = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
        reading = event2.meter_readings.build(meter: meter, value_kwh: 100)
        expect(reading).to be_valid
      end
    end

    context "when value is less than previous reading" do
      before do
        event1 = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        event1.meter_readings.create!(meter: meter, value_kwh: 100)
      end

      it "is invalid" do
        event2 = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")
        reading = event2.meter_readings.build(meter: meter, value_kwh: 50)
        expect(reading).not_to be_valid
        expect(reading.errors[:value_kwh]).to include(match(/musí být větší nebo roven předchozímu odečtu/))
      end
    end

    context "with multiple meters" do
      let(:secondary_meter) { Meter.create!(property: property, meter_type: "secondary", label: "Secondary", unit: "kWh") }

      before do
        event1 = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
        event1.meter_readings.create!(meter: meter, value_kwh: 100)
        event1.meter_readings.create!(meter: secondary_meter, value_kwh: 50)
      end

      it "validates each meter independently" do
        event2 = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_out")

        # Main meter can increase
        main_reading = event2.meter_readings.build(meter: meter, value_kwh: 150)
        expect(main_reading).to be_valid

        # Secondary meter validation is independent
        secondary_reading = event2.meter_readings.build(meter: secondary_meter, value_kwh: 40)
        expect(secondary_reading).not_to be_valid
        expect(secondary_reading.errors[:value_kwh]).to include(match(/musí být větší nebo roven předchozímu odečtu/))
      end
    end

    context "with soft-deleted readings" do
      before do
        event1 = MeterReadingEvent.create!(recorded_at: 2.days.ago, event_type: "check_in")
        reading1 = event1.meter_readings.create!(meter: meter, value_kwh: 100)

        event2 = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_out")
        reading2 = event2.meter_readings.create!(meter: meter, value_kwh: 150)
        reading2.discard
      end

      it "ignores discarded readings" do
        event3 = MeterReadingEvent.create!(recorded_at: Time.current, event_type: "check_in")
        reading = event3.meter_readings.build(meter: meter, value_kwh: 120)
        expect(reading).to be_valid
      end
    end
  end
end
