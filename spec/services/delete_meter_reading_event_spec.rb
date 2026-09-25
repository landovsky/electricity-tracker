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

  describe "correcting a mistyped reading by deleting its event" do
    let(:user) { create(:user) }
    let(:main_meter) { property.meters.find_by!(meter_type: "main") }
    let(:secondary_meter) { property.meters.find_by!(meter_type: "secondary") }
    let!(:earlier_stay) do
      create(:stay, :closed, visitor: create(:visitor, property: property), property: property,
             check_in_at: 5.days.ago, check_out_at: 4.days.ago,
             main_reading_in: 1000.0, main_reading_out: 1100.0,
             secondary_reading_in: 500.0, secondary_reading_out: 520.0)
    end
    let!(:typo_stay) do
      create(:stay, :open, visitor: visitor, property: property, check_in_at: 2.days.ago,
             main_reading_in: 99_999.0, secondary_reading_in: 88_888.0)
    end

    def check_in_again(main:)
      CheckInVisitor.run(visitor: visitor, property: property, recorded_by_user: user,
                         recorded_at: 1.day.ago, meter_readings: { main_meter.id.to_s => main.to_s })
    end

    it "discards the deleted event's readings along with the event" do
      described_class.run(event: typo_stay.check_in_event)

      expect(typo_stay.check_in_event.meter_readings.reload).to all(be_discarded)
    end

    it "stops the typo from being the meter's last reading, so the dashboard hint falls back" do
      described_class.run(event: typo_stay.check_in_event)

      expect(main_meter.last_reading.value_kwh).to eq(1100.0)
    end

    it "lets the visitor check in again with the correct, lower value (C1 no longer compares against the typo)" do
      described_class.run(event: typo_stay.check_in_event)

      outcome = check_in_again(main: 1150)

      expect(outcome).to be_valid, outcome.errors.full_messages.join(", ")
    end

    it "defaults a skipped secondary meter to the last live value, not the deleted one (C5)" do
      described_class.run(event: typo_stay.check_in_event)

      stay = check_in_again(main: 1150).result

      expect(stay.check_in_event.meter_readings.find_by(meter: secondary_meter).value_kwh).to eq(520.0)
    end

    context "the event was deleted by older code that left its readings kept" do
      before do
        typo_stay.discard!
        typo_stay.check_in_event.discard!
      end

      it "ignores those readings for the last reading, which also feeds the OCR matcher" do
        expect(main_meter.last_reading.value_kwh).to eq(1100.0)
      end

      it "does not let them block a correct check-in (C1 model validation)" do
        expect(check_in_again(main: 1150)).to be_valid
      end
    end
  end

  describe "deleting a check-out after the visitor already came back" do
    let!(:first_stay) do
      create(:stay, :closed, visitor: visitor, property: property,
             check_in_at: 10.days.ago, check_out_at: 8.days.ago,
             main_reading_in: 1000.0, main_reading_out: 1050.0)
    end
    let(:event) { first_stay.check_out_event }

    context "the visitor is currently checked in again" do
      let!(:second_stay) do
        create(:stay, :open, visitor: visitor, property: property, check_in_at: 2.days.ago,
               main_reading_in: 1100.0, secondary_reading_in: 600.0)
      end

      it "refuses, so the visitor never has two open stays (C2)" do
        outcome = described_class.run(event: event)

        expect(outcome).not_to be_valid
        expect(outcome.errors[:base]).to include(I18n.t("meter_reading_events.destroy.has_later_stay"))
        expect(first_stay.reload).to be_closed
        expect(event.reload).not_to be_discarded
      end
    end

    context "the visitor's later stay is already closed" do
      let!(:second_stay) do
        create(:stay, :closed, visitor: visitor, property: property,
               check_in_at: 4.days.ago, check_out_at: 3.days.ago,
               main_reading_in: 1100.0, main_reading_out: 1200.0,
               secondary_reading_in: 600.0, secondary_reading_out: 650.0)
      end

      it "refuses, so the reopened stay is not billed for the time the visitor was away" do
        outcome = described_class.run(event: event)

        expect(outcome).not_to be_valid
        expect(first_stay.reload).to be_closed
      end
    end

    context "the only other stay is a legacy orphan whose check-in was deleted" do
      let!(:orphan_stay) do
        create(:stay, :open, visitor: visitor, property: property, check_in_at: 2.days.ago,
               main_reading_in: 1100.0, secondary_reading_in: 600.0).tap { |s| s.check_in_event.discard! }
      end

      it "still reopens the stay, because the orphan is not a real presence" do
        outcome = described_class.run(event: event)

        expect(outcome).to be_valid
        expect(first_stay.reload).to be_open
      end
    end
  end

  describe "deleting a check-in when an older orphaned stay exists" do
    let!(:orphan_stay) do
      create(:stay, :open, visitor: visitor, property: property, check_in_at: 5.days.ago)
        .tap { |s| s.check_in_event.discard! }
    end
    let!(:stay) do
      create(:stay, :open, visitor: visitor, property: property, check_in_at: 1.day.ago, main_reading_in: 1200.0)
    end

    it "still works, so a wrong check-in can be removed" do
      outcome = described_class.run(event: stay.check_in_event)

      expect(outcome).to be_valid
      expect(stay.reload).to be_discarded
    end
  end

  describe "a failure halfway through deleting" do
    let!(:stay) { create(:stay, :open, visitor: visitor, property: property) }
    let(:event) { stay.check_in_event }

    it "rolls back the stay change, so a stay is never discarded while its check-in stays visible" do
      allow(event).to receive(:discard!).and_raise(ActiveRecord::StatementInvalid, "database is locked")

      expect { described_class.run(event: event) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(stay.reload).not_to be_discarded
      expect(event.meter_readings.reload).to all(be_kept)
    end
  end
end
