# frozen_string_literal: true

require 'rails_helper'

# Factory validation specs
#
# These specs verify that all FactoryBot factories produce valid records.
# Factories are located in spec/factories/ and use FFaker for realistic test data.
#
# To run these specs:
#   bundle exec rspec spec/factories_spec.rb
#
# Note: If DATABASE_URL is set to PostgreSQL in your environment, you may need to override it:
#   DATABASE_URL="sqlite3:storage/test.sqlite3" bundle exec rspec spec/factories_spec.rb

RSpec.describe "FactoryBot factories" do
  describe "property factory" do
    it "creates a valid property" do
      property = build(:property)
      expect(property).to be_valid
    end

    it "creates a property and persists it" do
      property = create(:property)
      expect(property).to be_persisted
      expect(property.name).to be_present
    end
  end

  describe "meter factory" do
    it "creates a valid meter with default main type" do
      meter = build(:meter)
      expect(meter).to be_valid
      expect(meter.meter_type).to eq("main")
    end

    it "creates a valid main meter using trait" do
      meter = build(:meter, :main)
      expect(meter).to be_valid
      expect(meter.meter_type).to eq("main")
      expect(meter.label).to eq("Main meter")
    end

    it "creates a valid secondary meter using trait" do
      meter = build(:meter, :secondary)
      expect(meter).to be_valid
      expect(meter.meter_type).to eq("secondary")
      expect(meter.label).to eq("Upper floor meter")
    end

    it "associates with a property" do
      meter = create(:meter)
      expect(meter.property).to be_present
    end

    it "enforces uniqueness of meter_type per property" do
      property = create(:property)
      create(:meter, :main, property: property)

      duplicate = build(:meter, :main, property: property)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:meter_type]).to be_present
    end
  end

  describe "visitor factory" do
    it "creates a valid visitor with default active status" do
      visitor = build(:visitor)
      expect(visitor).to be_valid
      expect(visitor.status).to eq("active")
    end

    it "creates an active visitor using trait" do
      visitor = build(:visitor, :active)
      expect(visitor).to be_valid
      expect(visitor.status).to eq("active")
    end

    it "creates an archived visitor using trait" do
      visitor = build(:visitor, :archived)
      expect(visitor).to be_valid
      expect(visitor.status).to eq("archived")
    end

    it "generates a name" do
      visitor = create(:visitor)
      expect(visitor.name).to be_present
    end
  end

  describe "user factory" do
    it "creates a valid user with default member role" do
      user = build(:user)
      expect(user).to be_valid
      expect(user.role).to eq("member")
    end

    it "creates an admin user using trait" do
      user = build(:user, :admin)
      expect(user).to be_valid
      expect(user.role).to eq("admin")
    end

    it "creates a member user using trait" do
      user = build(:user, :member)
      expect(user).to be_valid
      expect(user.role).to eq("member")
    end

    it "generates unique emails" do
      user1 = create(:user)
      user2 = create(:user)
      expect(user1.email).not_to eq(user2.email)
    end

    it "enforces email uniqueness" do
      user1 = create(:user)
      duplicate = build(:user, email: user1.email)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end
  end

  describe "meter_reading_event factory" do
    it "creates a valid meter_reading_event with default check_in type" do
      event = build(:meter_reading_event)
      expect(event).to be_valid
      expect(event.event_type).to eq("check_in")
    end

    it "creates a check_in event using trait" do
      event = build(:meter_reading_event, :check_in)
      expect(event).to be_valid
      expect(event.event_type).to eq("check_in")
    end

    it "creates a check_out event using trait" do
      event = build(:meter_reading_event, :check_out)
      expect(event).to be_valid
      expect(event.event_type).to eq("check_out")
    end

    it "associates with a user" do
      event = create(:meter_reading_event)
      expect(event.recorded_by_user).to be_present
    end

    it "has a recorded_at timestamp" do
      event = create(:meter_reading_event)
      expect(event.recorded_at).to be_present
    end

    it "creates meter readings when property and reading values are provided" do
      property = create(:property)
      create(:meter, :main, property: property)
      create(:meter, :secondary, property: property)

      event = create(:meter_reading_event,
        property: property,
        main_reading: 1000.0,
        secondary_reading: 500.0
      )

      expect(event.meter_readings.count).to eq(2)
      main_reading = event.meter_readings.find { |r| r.meter.main? }
      secondary_reading = event.meter_readings.find { |r| r.meter.secondary? }

      expect(main_reading.value_kwh).to eq(1000.0)
      expect(secondary_reading.value_kwh).to eq(500.0)
    end
  end

  describe "meter_reading factory" do
    it "creates a valid meter_reading" do
      reading = build(:meter_reading)
      expect(reading).to be_valid
    end

    it "generates sequential kWh values" do
      reading1 = create(:meter_reading)
      reading2 = create(:meter_reading)
      expect(reading2.value_kwh).to be > reading1.value_kwh
    end

    it "associates with a meter_reading_event" do
      reading = create(:meter_reading)
      expect(reading.meter_reading_event).to be_present
    end

    it "associates with a meter" do
      reading = create(:meter_reading)
      expect(reading.meter).to be_present
    end

    it "validates value_kwh is non-negative" do
      reading = build(:meter_reading, value_kwh: -10)
      expect(reading).not_to be_valid
      expect(reading.errors[:value_kwh]).to be_present
    end
  end

  describe "manual_consumption_entry factory" do
    it "creates a valid manual_consumption_entry" do
      entry = build(:manual_consumption_entry)
      expect(entry).to be_valid
    end

    it "associates with a visitor" do
      entry = create(:manual_consumption_entry)
      expect(entry.visitor).to be_present
    end

    it "associates with a property" do
      entry = create(:manual_consumption_entry)
      expect(entry.property).to be_present
    end

    it "associates with a user" do
      entry = create(:manual_consumption_entry)
      expect(entry.recorded_by_user).to be_present
    end

    it "generates a positive kWh value" do
      entry = create(:manual_consumption_entry)
      expect(entry.kwh).to be > 0
    end

    it "has a date and note" do
      entry = create(:manual_consumption_entry)
      expect(entry.date).to be_present
      expect(entry.note).to be_present
    end

    it "validates kwh is positive" do
      entry = build(:manual_consumption_entry, kwh: 0)
      expect(entry).not_to be_valid
      expect(entry.errors[:kwh]).to be_present
    end
  end

  describe "stay factory" do
    it "creates a valid open stay by default" do
      stay = create(:stay)
      expect(stay).to be_valid
      expect(stay.status).to eq("open")
      expect(stay.check_in_event).to be_present
      expect(stay.check_out_event).to be_nil
    end

    it "creates an open stay using trait" do
      stay = create(:stay, :open)
      expect(stay).to be_valid
      expect(stay.status).to eq("open")
      expect(stay.check_out_event).to be_nil
    end

    it "creates a closed stay using trait" do
      stay = create(:stay, :closed)
      expect(stay).to be_valid
      expect(stay.status).to eq("closed")
      expect(stay.check_in_event).to be_present
      expect(stay.check_out_event).to be_present
    end

    it "creates check-in event with meter readings" do
      stay = create(:stay)
      expect(stay.check_in_event).to be_present
      expect(stay.check_in_event.meter_readings.count).to eq(2)

      main_reading = stay.check_in_event.meter_readings.find { |r| r.meter.main? }
      secondary_reading = stay.check_in_event.meter_readings.find { |r| r.meter.secondary? }

      expect(main_reading).to be_present
      expect(secondary_reading).to be_present
    end

    it "creates check-out event with meter readings for closed stays" do
      stay = create(:stay, :closed)
      expect(stay.check_out_event).to be_present
      expect(stay.check_out_event.meter_readings.count).to eq(2)

      main_reading = stay.check_out_event.meter_readings.find { |r| r.meter.main? }
      secondary_reading = stay.check_out_event.meter_readings.find { |r| r.meter.secondary? }

      expect(main_reading).to be_present
      expect(secondary_reading).to be_present
    end

    it "ensures check-out readings are greater than check-in readings" do
      stay = create(:stay, :closed,
        main_reading_in: 1000.0,
        main_reading_out: 1050.0,
        secondary_reading_in: 500.0,
        secondary_reading_out: 525.0
      )

      expect(stay).to be_valid

      main_in = stay.check_in_event.meter_readings.find { |r| r.meter.main? }.value_kwh
      main_out = stay.check_out_event.meter_readings.find { |r| r.meter.main? }.value_kwh
      expect(main_out).to be > main_in

      secondary_in = stay.check_in_event.meter_readings.find { |r| r.meter.secondary? }.value_kwh
      secondary_out = stay.check_out_event.meter_readings.find { |r| r.meter.secondary? }.value_kwh
      expect(secondary_out).to be > secondary_in
    end

    it "associates with a visitor" do
      stay = create(:stay)
      expect(stay.visitor).to be_present
    end

    it "associates with a property" do
      stay = create(:stay)
      expect(stay.property).to be_present
    end

    it "creates property meters automatically" do
      stay = create(:stay)
      expect(stay.property.meters.count).to eq(2)
      expect(stay.property.meters.main).to be_present
      expect(stay.property.meters.secondary).to be_present
    end

    it "enforces one open stay per visitor (C2)" do
      visitor = create(:visitor)
      property = create(:property)
      create(:stay, :open, visitor: visitor, property: property)

      duplicate = build(:stay, :open, visitor: visitor, property: property)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:base]).to include("Visitor already has an open stay")
    end

    it "allows multiple closed stays for the same visitor" do
      visitor = create(:visitor)
      property = create(:property)

      stay1 = create(:stay, :closed, visitor: visitor, property: property,
        check_in_at: 5.days.ago,
        check_out_at: 3.days.ago,
        main_reading_in: 1000.0,
        main_reading_out: 1050.0,
        secondary_reading_in: 500.0,
        secondary_reading_out: 525.0
      )

      stay2 = create(:stay, :closed, visitor: visitor, property: property,
        check_in_at: 2.days.ago,
        check_out_at: 1.day.ago,
        main_reading_in: 1050.0,
        main_reading_out: 1100.0,
        secondary_reading_in: 525.0,
        secondary_reading_out: 550.0
      )

      expect(stay1).to be_valid
      expect(stay2).to be_valid
    end

    it "allows customizing check-in and check-out times" do
      stay = create(:stay, :closed,
        check_in_at: 7.days.ago,
        check_out_at: 2.days.ago
      )

      expect(stay.check_in_event.recorded_at).to be_within(1.second).of(7.days.ago)
      expect(stay.check_out_event.recorded_at).to be_within(1.second).of(2.days.ago)
    end

    it "allows customizing meter reading values" do
      stay = create(:stay,
        main_reading_in: 2500.0,
        secondary_reading_in: 1200.0
      )

      main_reading = stay.check_in_event.meter_readings.find { |r| r.meter.main? }
      secondary_reading = stay.check_in_event.meter_readings.find { |r| r.meter.secondary? }

      expect(main_reading.value_kwh).to eq(2500.0)
      expect(secondary_reading.value_kwh).to eq(1200.0)
    end
  end

  describe "factory combinations" do
    it "creates a complete scenario with property, meters, visitors, and stays" do
      property = create(:property)
      visitor1 = create(:visitor)
      visitor2 = create(:visitor)

      stay1 = create(:stay, :closed,
        property: property,
        visitor: visitor1,
        check_in_at: 10.days.ago,
        check_out_at: 5.days.ago,
        main_reading_in: 1000.0,
        main_reading_out: 1100.0,
        secondary_reading_in: 500.0,
        secondary_reading_out: 550.0
      )

      stay2 = create(:stay, :open,
        property: property,
        visitor: visitor2,
        check_in_at: 3.days.ago,
        main_reading_in: 1100.0,
        secondary_reading_in: 550.0
      )

      expect(property.stays.count).to eq(2)
      expect(property.stays.open.count).to eq(1)
      expect(property.stays.closed.count).to eq(1)
      expect(visitor1.stays.closed.count).to eq(1)
      expect(visitor2.stays.open.count).to eq(1)
    end

    it "creates manual consumption entries alongside stays" do
      property = create(:property)
      visitor = create(:visitor)
      user = create(:user)

      stay = create(:stay, :closed,
        property: property,
        visitor: visitor,
        recorded_by: user,
        check_in_at: 5.days.ago,
        check_out_at: 2.days.ago
      )

      entry = create(:manual_consumption_entry,
        property: property,
        visitor: visitor,
        recorded_by_user: user,
        date: 3.days.ago,
        kwh: 15.0,
        note: "EV charging"
      )

      expect(visitor.stays.count).to eq(1)
      expect(visitor.manual_consumption_entries.count).to eq(1)
      expect(entry.kwh).to eq(15.0)
    end
  end
end
