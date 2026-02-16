require 'rails_helper'

RSpec.describe ManualConsumptionEntry, type: :model do
  describe "associations" do
    it { should belong_to(:visitor) }
    it { should belong_to(:property) }
    it { should belong_to(:recorded_by_user).class_name("User").optional }
  end

  describe "validations" do
    it { should validate_presence_of(:date) }
    it { should validate_presence_of(:kwh) }
    it { should validate_presence_of(:note) }
    it { should validate_numericality_of(:kwh).is_greater_than(0) }
  end

  describe "audit trail" do
    it "is audited" do
      expect(ManualConsumptionEntry.new).to respond_to(:audits)
    end
  end

  describe "soft deletes" do
    it "includes Discard::Model" do
      expect(ManualConsumptionEntry.included_modules).to include(Discard::Model)
    end
  end

  describe "scopes" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }

    before do
      ManualConsumptionEntry.create!(visitor: visitor, property: property, date: 3.days.ago, kwh: 10, note: "Entry 1")
      ManualConsumptionEntry.create!(visitor: visitor, property: property, date: 1.day.ago, kwh: 20, note: "Entry 2")
      ManualConsumptionEntry.create!(visitor: visitor, property: property, date: Time.zone.today, kwh: 15, note: "Entry 3")
    end

    describe ".recent" do
      it "returns entries in reverse chronological order" do
        entries = ManualConsumptionEntry.recent
        expect(entries.pluck(:kwh)).to eq([15, 20, 10])
      end
    end

    describe ".for_date_range" do
      it "returns entries within the specified date range" do
        entries = ManualConsumptionEntry.for_date_range(2.days.ago, Time.zone.today)
        expect(entries.count).to eq(2)
        expect(entries.pluck(:kwh)).to match_array([20, 15])
      end

      it "includes entries on the boundary dates" do
        entries = ManualConsumptionEntry.for_date_range(3.days.ago, 1.day.ago)
        expect(entries.count).to eq(2)
        expect(entries.pluck(:kwh)).to match_array([10, 20])
      end
    end
  end

  describe "C7: positive kWh values" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }

    it "is valid with positive kWh" do
      entry = ManualConsumptionEntry.new(
        visitor: visitor,
        property: property,
        date: Time.zone.today,
        kwh: 15.5,
        note: "EV charging"
      )
      expect(entry).to be_valid
    end

    it "is invalid with zero kWh" do
      entry = ManualConsumptionEntry.new(
        visitor: visitor,
        property: property,
        date: Time.zone.today,
        kwh: 0,
        note: "Test"
      )
      expect(entry).not_to be_valid
      expect(entry.errors[:kwh]).to be_present
    end

    it "is invalid with negative kWh" do
      entry = ManualConsumptionEntry.new(
        visitor: visitor,
        property: property,
        date: Time.zone.today,
        kwh: -10,
        note: "Test"
      )
      expect(entry).not_to be_valid
      expect(entry.errors[:kwh]).to be_present
    end
  end

  describe "C8: soft validation for exceeding period consumption" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }

    it "has exceeds_period_consumption? method" do
      entry = ManualConsumptionEntry.new(
        visitor: visitor,
        property: property,
        date: Time.zone.today,
        kwh: 100,
        note: "Large entry"
      )
      expect(entry).to respond_to(:exceeds_period_consumption?)
    end

    it "has consumption_warning method" do
      entry = ManualConsumptionEntry.new(
        visitor: visitor,
        property: property,
        date: Time.zone.today,
        kwh: 100,
        note: "Large entry"
      )
      expect(entry).to respond_to(:consumption_warning)
    end

    it "returns nil warning when not exceeding" do
      entry = ManualConsumptionEntry.new(
        visitor: visitor,
        property: property,
        date: Time.zone.today,
        kwh: 10,
        note: "Small entry"
      )
      allow(entry).to receive(:exceeds_period_consumption?).and_return(false)
      expect(entry.consumption_warning).to be_nil
    end

    it "returns warning message when exceeding" do
      entry = ManualConsumptionEntry.new(
        visitor: visitor,
        property: property,
        date: Time.zone.today,
        kwh: 100,
        note: "Large entry"
      )
      allow(entry).to receive(:exceeds_period_consumption?).and_return(true)
      expect(entry.consumption_warning).to include("Warning")
      expect(entry.consumption_warning).to include("100")
    end
  end

  describe "edge case: manual entry during empty house (E4)" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }

    it "allows manual entry when no stays are active" do
      # No stays exist
      entry = ManualConsumptionEntry.new(
        visitor: visitor,
        property: property,
        date: Time.zone.today,
        kwh: 15,
        note: "EV charging while house empty"
      )
      expect(entry).to be_valid
    end
  end

  describe "edge case: manual entry during active stay (E5)" do
    let(:property) { Property.create!(name: "Test Property") }
    let(:visitor) { Visitor.create!(name: "Test Visitor", status: "active") }

    it "allows manual entry when visitor has an active stay" do
      check_in = MeterReadingEvent.create!(recorded_at: 1.day.ago, event_type: "check_in")
      Stay.create!(visitor: visitor, property: property, check_in_event: check_in)

      entry = ManualConsumptionEntry.new(
        visitor: visitor,
        property: property,
        date: Time.zone.today,
        kwh: 15,
        note: "EV charging during stay"
      )
      expect(entry).to be_valid
    end
  end
end
