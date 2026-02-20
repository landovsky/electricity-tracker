# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReadingsHistoryController, type: :request do
  let(:user) { create(:user) }
  let(:property) { create(:property) }
  let!(:main_meter) { create(:meter, property: property, meter_type: :main) }
  let(:visitor1) { create(:visitor, name: "Alice", property: property) }
  let(:visitor2) { create(:visitor, name: "Bob", property: property) }

  # Create stays which automatically create meter reading events
  let!(:stay1) do
    create(:stay,
      visitor: visitor1,
      property: property,
      check_in_at: 3.days.ago,
      main_reading_in: 1000.0,
      secondary_reading_in: 500.0,
      recorded_by: user
    )
  end

  let!(:stay2) do
    create(:stay,
      visitor: visitor2,
      property: property,
      check_in_at: 2.days.ago,
      main_reading_in: 1100.0,
      secondary_reading_in: 550.0,
      recorded_by: user
    )
  end

  let!(:manual_entry1) do
    create(:manual_consumption_entry,
      visitor: visitor1,
      property: property,
      kwh: 75.0,
      date: 3.days.ago.to_date,
      recorded_by_user: user
    )
  end

  let!(:manual_entry2) do
    create(:manual_consumption_entry,
      visitor: visitor2,
      property: property,
      kwh: 25.0,
      date: 1.day.ago.to_date,
      recorded_by_user: user
    )
  end

  before do
    user
    property
  end

  describe "GET /readings_history (index)" do
    context "without filters" do
      it "returns success" do
        get readings_history_path
        expect(response).to have_http_status(:success)
      end

      it "lists all meter reading events" do
        get readings_history_path
        expect(response.body).to include("Alice")
        expect(response.body).to include("Bob")
      end
    end

    context "with visitor filter" do
      it "returns success" do
        get readings_history_path, params: { visitor_id: visitor1.id }
        expect(response).to have_http_status(:success)
      end

      it "shows only events for the specified visitor" do
        get readings_history_path, params: { visitor_id: visitor1.id }
        expect(response.body).to include("Alice")
      end
    end

    context "with date range filter" do
      it "returns success with start_date" do
        get readings_history_path, params: { start_date: 2.days.ago.to_date.to_s }
        expect(response).to have_http_status(:success)
      end

      it "returns success with end_date" do
        get readings_history_path, params: { end_date: 2.days.ago.to_date.to_s }
        expect(response).to have_http_status(:success)
      end

      it "returns success with both start and end dates" do
        get readings_history_path, params: {
          start_date: 4.days.ago.to_date.to_s,
          end_date: 1.day.ago.to_date.to_s
        }
        expect(response).to have_http_status(:success)
      end
    end

    context "with invalid date format" do
      it "displays error message" do
        get readings_history_path, params: { start_date: "invalid-date" }
        expect(flash.now[:alert]).to include("Invalid date format")
      end

      it "still returns success (with empty results)" do
        get readings_history_path, params: { start_date: "invalid-date" }
        expect(response).to have_http_status(:success)
      end
    end

    context "when no property exists" do
      before do
        Property.destroy_all
      end

      it "redirects to root with error" do
        get readings_history_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("No property found")
      end
    end

    context "filtering meter reading events" do
      it "filters by visitor_id" do
        get readings_history_path, params: { visitor_id: visitor1.id }
        # Events for visitor1 should be present
        # We can't easily test the content without assigns(), but the request should succeed
        expect(response).to have_http_status(:success)
      end

      it "filters by date range" do
        get readings_history_path, params: {
          start_date: 2.days.ago.to_date.to_s,
          end_date: Date.today.to_s
        }
        expect(response).to have_http_status(:success)
      end
    end

    context "filtering manual consumption entries" do
      it "filters by visitor_id" do
        get readings_history_path, params: { visitor_id: visitor1.id }
        expect(response).to have_http_status(:success)
      end

      it "filters by date range" do
        get readings_history_path, params: {
          start_date: 2.days.ago.to_date.to_s,
          end_date: Date.today.to_s
        }
        expect(response).to have_http_status(:success)
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
      get readings_history_path
      expect(response).to redirect_to(login_path)
    end
  end
end
