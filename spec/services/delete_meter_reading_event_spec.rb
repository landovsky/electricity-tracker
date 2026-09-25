# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeleteMeterReadingEvent, type: :service do
  let(:property) { create(:property) }
  let(:visitor) { create(:visitor, property: property) }

  describe "deleting a check-in event (open stay)" do
    let!(:stay) { create(:stay, :open, visitor: visitor, property: property) }
    let(:event) { stay.check_in_event }

    it "discards the associated stay" do
      outcome = described_class.run(event: event)

      expect(outcome).to be_valid
      expect(stay.reload).to be_discarded
    end

    it "discards the event" do
      described_class.run(event: event)

      expect(event.reload).to be_discarded
    end

    it "removes the visitor from current_visitors" do
      expect(property.current_visitors).to include(visitor)

      described_class.run(event: event)

      expect(property.reload.current_visitors).not_to include(visitor)
    end

    it "allows the visitor to check in again" do
      described_class.run(event: event)

      new_stay = build(:stay, :open, visitor: visitor, property: property)
      expect(new_stay).to be_valid
    end
  end

  describe "deleting a check-in event (closed stay)" do
    let(:stay) { create(:stay, :closed, visitor: visitor, property: property) }
    let(:event) { stay.check_in_event }

    it "is blocked by validation" do
      outcome = described_class.run(event: event)

      expect(outcome).not_to be_valid
      expect(outcome.errors[:base]).to be_present
    end

    it "does not discard the event" do
      described_class.run(event: event)

      expect(event.reload).not_to be_discarded
    end

    it "does not discard the stay" do
      described_class.run(event: event)

      expect(stay.reload).not_to be_discarded
    end
  end

  describe "deleting a check-out event" do
    let(:stay) { create(:stay, :closed, visitor: visitor, property: property) }
    let(:event) { stay.check_out_event }

    it "reopens the stay by nullifying check_out_event_id" do
      described_class.run(event: event)

      expect(stay.reload.check_out_event_id).to be_nil
      expect(stay.reload).to be_open
    end

    it "discards the event" do
      described_class.run(event: event)

      expect(event.reload).to be_discarded
    end

    it "makes the visitor appear as present again" do
      expect(property.current_visitors).not_to include(visitor)

      described_class.run(event: event)

      expect(property.current_visitors).to include(visitor)
    end

    it "does not discard the stay" do
      described_class.run(event: event)

      expect(stay.reload).not_to be_discarded
    end
  end

  describe "deleting a periodic/initial event" do
    let(:event) { create(:meter_reading_event, event_type: "periodic", property: property, main_reading: 1200.0) }

    it "discards the event without affecting stays" do
      stay = create(:stay, :open, visitor: visitor, property: property)

      described_class.run(event: event)

      expect(event.reload).to be_discarded
      expect(stay.reload).not_to be_discarded
      expect(stay).to be_open
    end
  end
end
