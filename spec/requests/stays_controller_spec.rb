# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StaysController, type: :request do
  let(:user) { create(:user) }
  let(:property) { create(:property) }
  let!(:main_meter) { create(:meter, property: property, meter_type: :main, label: "Main meter") }
  let!(:secondary_meter) { create(:meter, property: property, meter_type: :secondary, label: "Upper floor meter") }
  let(:visitor) { create(:visitor, property: property) }

  before do
    property # ensure property exists
    user
  end

  describe "POST /stays (check-in)" do
    let(:valid_params) do
      {
        visitor_id: visitor.id,
        property_id: property.id,
        recorded_at: Time.current.iso8601,
        main_meter_reading: 1000.0,
        secondary_meter_reading: 500.0,
        note: "Arriving for weekend"
      }
    end

    context "with valid parameters" do
      it "creates a new stay" do
        expect {
          post stays_path, params: valid_params
        }.to change(Stay, :count).by(1)
      end

      it "creates a meter reading event" do
        expect {
          post stays_path, params: valid_params
        }.to change(MeterReadingEvent, :count).by(1)
      end

      it "creates meter readings for both meters" do
        expect {
          post stays_path, params: valid_params
        }.to change(MeterReading, :count).by(2)
      end

      it "redirects to root with success notice" do
        post stays_path, params: valid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("check-in recorded")
      end

      it "associates the stay with the visitor and property" do
        post stays_path, params: valid_params
        stay = Stay.last
        expect(stay.visitor).to eq(visitor)
        expect(stay.property).to eq(property)
      end

      it "creates an open stay" do
        post stays_path, params: valid_params
        stay = Stay.last
        expect(stay.open?).to be true
        expect(stay.check_out_event).to be_nil
      end
    end

    context "with minimal parameters (using defaults)" do
      let(:minimal_params) do
        {
          visitor_id: visitor.id,
          main_meter_reading: 1000.0
        }
      end

      it "creates a stay with default property" do
        post stays_path, params: minimal_params
        expect(response).to redirect_to(root_path)
        stay = Stay.last
        expect(stay.property).to eq(property)
      end

      it "uses current time when recorded_at is not provided" do
        post stays_path, params: minimal_params
        stay = Stay.last
        expect(stay.check_in_event.recorded_at).to be_within(2.seconds).of(Time.current)
      end

      it "creates stay without secondary meter reading" do
        post stays_path, params: minimal_params
        stay = Stay.last
        main_reading = stay.check_in_event.meter_readings.find_by(meter: main_meter)
        expect(main_reading.value_kwh).to eq(1000.0)
      end
    end

    context "with invalid parameters" do
      it "redirects with error when visitor does not exist" do
        invalid_params = valid_params.merge(visitor_id: 99999)
        post stays_path, params: invalid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end

      it "does not create a stay when visitor_id is missing" do
        invalid_params = valid_params.except(:visitor_id)
        expect {
          post stays_path, params: invalid_params
        }.not_to change(Stay, :count)
      end

      it "redirects with error when main_meter_reading is missing" do
        invalid_params = valid_params.except(:main_meter_reading)
        post stays_path, params: invalid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "constraint validation - C2: visitor already has open stay" do
      let!(:existing_stay) { create(:stay, :open, visitor: visitor, property: property) }

      it "redirects with error" do
        post stays_path, params: valid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("already has an open stay")
      end

      it "does not create a new stay" do
        expect {
          post stays_path, params: valid_params
        }.not_to change(Stay, :count)
      end
    end

    context "constraint validation - C1: meter readings must be monotonically non-decreasing" do
      before do
        # Create a previous reading event
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

      it "rejects reading lower than previous reading" do
        invalid_params = valid_params.merge(main_meter_reading: 900.0)
        post stays_path, params: invalid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("must be greater than or equal to previous reading")
      end

      it "accepts reading equal to previous reading" do
        same_params = valid_params.merge(main_meter_reading: 1000.0)
        post stays_path, params: same_params
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("check-in recorded")
      end

      it "accepts reading higher than previous reading" do
        higher_params = valid_params.merge(main_meter_reading: 1100.0)
        post stays_path, params: higher_params
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("check-in recorded")
      end
    end

    context "constraint validation - C6: chronological consistency" do
      before do
        # Create a previous reading event in the future with meter readings for this property
        create(:meter_reading_event,
          event_type: :check_in,
          recorded_at: 1.day.from_now,
          recorded_by_user: user,
          property: property,
          main_reading: 2000.0
        )
      end

      it "rejects reading with timestamp before previous event" do
        past_params = valid_params.merge(recorded_at: Time.current.iso8601)
        post stays_path, params: past_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("must be after or equal to previous event")
      end
    end
  end

  describe "PATCH /stays/:id/check_out" do
    let!(:open_stay) do
      create(:stay, :open,
        visitor: visitor,
        property: property,
        check_in_at: 2.days.ago,
        main_reading_in: 1000.0,
        secondary_reading_in: 500.0,
        recorded_by: user
      )
    end

    let(:valid_params) do
      {
        recorded_at: Time.current.iso8601,
        main_meter_reading: 1050.0,
        secondary_meter_reading: 525.0,
        note: "Leaving after weekend"
      }
    end

    context "with valid parameters" do
      it "closes the stay" do
        patch check_out_stay_path(open_stay), params: valid_params
        open_stay.reload
        expect(open_stay.closed?).to be true
      end

      it "creates a check-out meter reading event" do
        expect {
          patch check_out_stay_path(open_stay), params: valid_params
        }.to change(MeterReadingEvent.where(event_type: :check_out), :count).by(1)
      end

      it "creates meter readings for both meters" do
        expect {
          patch check_out_stay_path(open_stay), params: valid_params
        }.to change(MeterReading, :count).by(2)
      end

      it "redirects to root with success notice" do
        patch check_out_stay_path(open_stay), params: valid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("check-out recorded")
      end

      it "associates the check-out event with the stay" do
        patch check_out_stay_path(open_stay), params: valid_params
        open_stay.reload
        expect(open_stay.check_out_event).to be_present
        expect(open_stay.check_out_event.event_type).to eq("check_out")
      end
    end

    context "with minimal parameters (using defaults)" do
      let(:minimal_params) do
        {
          main_meter_reading: 1050.0
        }
      end

      it "closes the stay" do
        patch check_out_stay_path(open_stay), params: minimal_params
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("check-out recorded")
      end

      it "uses current time when recorded_at is not provided" do
        patch check_out_stay_path(open_stay), params: minimal_params
        open_stay.reload
        expect(open_stay.check_out_event.recorded_at).to be_within(2.seconds).of(Time.current)
      end
    end

    context "with invalid parameters" do
      it "returns error when stay does not exist" do
        patch check_out_stay_path(id: 99999), params: valid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("Stay not found")
      end

      it "returns error when main_meter_reading is missing" do
        invalid_params = valid_params.except(:main_meter_reading)
        patch check_out_stay_path(open_stay), params: invalid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end

      it "does not close stay when validation fails" do
        invalid_params = valid_params.merge(main_meter_reading: 900.0) # Lower than check-in
        patch check_out_stay_path(open_stay), params: invalid_params
        open_stay.reload
        expect(open_stay.open?).to be true
      end
    end

    context "constraint validation - C3: check-out reading >= check-in reading" do
      it "rejects check-out reading lower than check-in reading" do
        invalid_params = valid_params.merge(main_meter_reading: 900.0) # Lower than 1000.0
        patch check_out_stay_path(open_stay), params: invalid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("must be greater than or equal to check-in reading")
      end

      it "accepts check-out reading equal to check-in reading (E3: same-day check-in/out)" do
        same_params = valid_params.merge(main_meter_reading: 1000.0)
        patch check_out_stay_path(open_stay), params: same_params
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("check-out recorded")
      end

      it "accepts check-out reading higher than check-in reading" do
        higher_params = valid_params.merge(main_meter_reading: 1100.0)
        patch check_out_stay_path(open_stay), params: higher_params
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("check-out recorded")
      end
    end

    context "constraint validation - C1: monotonic meter readings" do
      before do
        # Create another stay that was checked out after this one's check-in
        another_visitor = create(:visitor)
        another_stay = create(:stay, :open,
          visitor: another_visitor,
          property: property,
          check_in_at: 1.day.ago,
          main_reading_in: 1100.0,
          recorded_by: user
        )
        CheckOutVisitor.run(
          stay: another_stay,
          property: property,
          recorded_by_user: user,
          recorded_at: 1.hour.ago,
          main_meter_reading: 1150.0,
          secondary_meter_reading: 575.0
        )
      end

      it "rejects reading lower than the last known reading" do
        invalid_params = valid_params.merge(
          main_meter_reading: 1100.0, # Lower than 1150.0
          recorded_at: Time.current.iso8601
        )
        patch check_out_stay_path(open_stay), params: invalid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("must be greater than or equal to the previous reading")
      end
    end

    context "edge case - E8: secondary meter reading optional" do
      it "allows check-out without secondary meter reading" do
        params_without_secondary = valid_params.except(:secondary_meter_reading)
        patch check_out_stay_path(open_stay), params: params_without_secondary
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("check-out recorded")
      end

      it "defaults secondary meter to last known value when not provided" do
        params_without_secondary = valid_params.except(:secondary_meter_reading)
        patch check_out_stay_path(open_stay), params: params_without_secondary
        open_stay.reload
        secondary_reading = open_stay.check_out_event.meter_readings.find_by(meter: secondary_meter)
        expect(secondary_reading.value_kwh).to eq(500.0) # Same as check-in
      end
    end

    context "when stay is already closed" do
      let(:another_visitor) { create(:visitor) }
      let!(:closed_stay) do
        create(:stay, :closed,
          visitor: another_visitor,
          property: property,
          recorded_by: user
        )
      end

      it "returns error" do
        patch check_out_stay_path(closed_stay), params: valid_params
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("already closed")
      end
    end
  end

  context "when not authenticated" do
    before do
      # Undo the auto-sign-in from authentication_helpers.rb
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_call_original
      allow_any_instance_of(ApplicationController).to receive(:logged_in?).and_call_original
    end

    it "redirects to login" do
      post stays_path, params: { visitor_id: visitor.id, main_meter_reading: 1000.0 }
      expect(response).to redirect_to(login_path)
    end
  end
end
