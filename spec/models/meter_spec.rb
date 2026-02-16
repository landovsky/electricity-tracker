require 'rails_helper'

RSpec.describe Meter, type: :model do
  describe "associations" do
    it { should belong_to(:property) }
    it { should have_many(:meter_readings).dependent(:destroy) }
  end

  describe "validations" do
    subject { described_class.new(property: Property.create!(name: "Test Property"), meter_type: "main", label: "Main", unit: "kWh") }

    it { should validate_presence_of(:meter_type) }
    it { should validate_presence_of(:label) }
    it { should validate_presence_of(:unit) }
    it { should validate_uniqueness_of(:meter_type).scoped_to(:property_id) }
  end

  describe "enums" do
    it { should define_enum_for(:meter_type).backed_by_column_of_type(:string).with_values(main: "main", secondary: "secondary") }

    it "validates enum values" do
      property = Property.create!(name: "Test Property")
      meter = Meter.new(property: property, meter_type: "invalid", label: "Test", unit: "kWh")
      expect(meter).not_to be_valid
      expect(meter.errors[:meter_type]).to be_present
    end
  end

  describe "scopes" do
    let(:property) { Property.create!(name: "Test Property") }

    before do
      Meter.create!(property: property, meter_type: "main", label: "Main Meter", unit: "kWh")
      Meter.create!(property: property, meter_type: "secondary", label: "Secondary Meter", unit: "kWh")
    end

    describe ".main" do
      it "returns only main meters" do
        expect(Meter.main.count).to eq(1)
        expect(Meter.main.first.meter_type).to eq("main")
      end
    end

    describe ".secondary" do
      it "returns only secondary meters" do
        expect(Meter.secondary.count).to eq(1)
        expect(Meter.secondary.first.meter_type).to eq("secondary")
      end
    end
  end

  describe "soft deletes" do
    it "includes Discard::Model" do
      expect(Meter.included_modules).to include(Discard::Model)
    end
  end
end
