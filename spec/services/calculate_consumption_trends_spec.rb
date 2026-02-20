# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalculateConsumptionTrends, type: :service do
  let(:property) { create(:property, tracking_mode: :meter_only) }
  let(:meter) { create(:meter, property: property, meter_type: :main, label: "Main") }
  let(:user) { create(:user) }

  def create_event(recorded_at:, reading:, event_type: :periodic)
    event = create(:meter_reading_event,
      recorded_at: recorded_at,
      event_type: event_type,
      recorded_by_user: user)

    create(:meter_reading,
      meter_reading_event: event,
      meter: meter,
      value_kwh: reading)

    event
  end

  describe "#execute" do
    context "with no events" do
      it "returns empty result" do
        outcome = described_class.run(
          property: property,
          start_date: Date.new(2025, 1, 1),
          end_date: Date.new(2025, 12, 31)
        )

        expect(outcome).to be_valid
        expect(outcome.result[:months]).to eq([])
        expect(outcome.result[:total_kwh]).to eq(0.0)
      end
    end

    context "with single event" do
      it "returns empty result (needs at least 2 for a delta)" do
        create_event(recorded_at: Time.zone.local(2025, 1, 15, 10, 0), reading: 1000, event_type: :initial)

        outcome = described_class.run(
          property: property,
          start_date: Date.new(2025, 1, 1),
          end_date: Date.new(2025, 12, 31)
        )

        expect(outcome).to be_valid
        expect(outcome.result[:months]).to eq([])
      end
    end

    context "with multiple events across months" do
      before do
        create_event(recorded_at: Time.zone.local(2025, 1, 1, 10, 0), reading: 1000, event_type: :initial)
        create_event(recorded_at: Time.zone.local(2025, 2, 1, 10, 0), reading: 1450)
        create_event(recorded_at: Time.zone.local(2025, 3, 1, 10, 0), reading: 1800)
        create_event(recorded_at: Time.zone.local(2025, 4, 1, 10, 0), reading: 2100)
      end

      it "computes monthly deltas" do
        outcome = described_class.run(
          property: property,
          start_date: Date.new(2025, 1, 1),
          end_date: Date.new(2025, 12, 31)
        )

        expect(outcome).to be_valid
        months = outcome.result[:months]
        expect(months.size).to eq(3)

        expect(months[0][:month]).to eq(Date.new(2025, 2, 1))
        expect(months[0][:total_kwh]).to eq(450.0)
        expect(months[0][:readings_count]).to eq(1)

        expect(months[1][:month]).to eq(Date.new(2025, 3, 1))
        expect(months[1][:total_kwh]).to eq(350.0)

        expect(months[2][:month]).to eq(Date.new(2025, 4, 1))
        expect(months[2][:total_kwh]).to eq(300.0)

        expect(outcome.result[:total_kwh]).to eq(1100.0)
      end

      it "filters by date range" do
        outcome = described_class.run(
          property: property,
          start_date: Date.new(2025, 2, 1),
          end_date: Date.new(2025, 3, 31)
        )

        expect(outcome).to be_valid
        months = outcome.result[:months]
        # Boundary event (Jan 1) + Feb 1 + Mar 1 + Apr 1 (within end_of_day Mar 31? No, Apr 1 is outside)
        # So: boundary=Jan1, in_range=Feb1,Mar1 => deltas for Feb and Mar
        expect(months.size).to eq(2)
        expect(months[0][:total_kwh]).to eq(450.0) # Jan->Feb delta
        expect(months[1][:total_kwh]).to eq(350.0) # Feb->Mar delta
      end
    end

    context "with multiple readings in same month" do
      before do
        create_event(recorded_at: Time.zone.local(2025, 1, 1, 10, 0), reading: 1000, event_type: :initial)
        create_event(recorded_at: Time.zone.local(2025, 1, 15, 10, 0), reading: 1200)
        create_event(recorded_at: Time.zone.local(2025, 1, 31, 10, 0), reading: 1500)
      end

      it "aggregates deltas within the same month" do
        outcome = described_class.run(
          property: property,
          start_date: Date.new(2025, 1, 1),
          end_date: Date.new(2025, 1, 31)
        )

        expect(outcome).to be_valid
        months = outcome.result[:months]
        expect(months.size).to eq(1)
        expect(months[0][:total_kwh]).to eq(500.0) # 200 + 300
        expect(months[0][:readings_count]).to eq(2)
      end
    end

    context "with invalid date range" do
      it "returns error" do
        outcome = described_class.run(
          property: property,
          start_date: Date.new(2025, 12, 31),
          end_date: Date.new(2025, 1, 1)
        )

        expect(outcome).not_to be_valid
      end
    end
  end
end
