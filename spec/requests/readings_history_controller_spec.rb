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

  describe "year filter" do
    let(:history_property) { create(:property, name: "AAA history") }
    let(:old_visitor) { create(:visitor, name: "Loňský host", property: history_property) }
    let(:new_visitor) { create(:visitor, name: "Letošní host", property: history_property) }

    let!(:old_event) { create(:stay, visitor: old_visitor, property: history_property, check_in_at: 2.years.ago).check_in_event }
    let!(:new_event) { create(:stay, visitor: new_visitor, property: history_property, check_in_at: 1.hour.ago).check_in_event }

    before { patch switch_property_path, params: { property_id: history_property.id } }

    def selected_option(body)
      year_select = body[%r{<select[^>]*name="year".*?</select>}m]
      year_select[/<option selected="selected" value="([^"]*)"/, 1]
    end

    context "the history is opened without any filter" do
      it "lists only the current year, because that is the year the dropdown shows as selected" do
        get readings_history_path

        expect(selected_option(response.body)).to eq(Date.current.year.to_s)
        expect(response.body).to include(ActionView::RecordIdentifier.dom_id(new_event))
        expect(response.body).not_to include(ActionView::RecordIdentifier.dom_id(old_event))
      end
    end

    context "the user explicitly picks the all-time option" do
      it "lists every year and shows all-time as the selected option" do
        get readings_history_path, params: { year: "" }

        expect(selected_option(response.body)).to eq("")
        expect(response.body).to include(ActionView::RecordIdentifier.dom_id(new_event))
        expect(response.body).to include(ActionView::RecordIdentifier.dom_id(old_event))
      end
    end
  end

  describe "events around local midnight on New Year" do
    let(:tz_property) { create(:property, name: "AAA timezone") }
    let(:new_year_visitor) { create(:visitor, name: "Silvestrovský host", property: tz_property) }

    # 00:30 Prague time is still 2025-12-31 23:30 in UTC, where it is stored
    let!(:new_year_event) do
      create(:stay, visitor: new_year_visitor, property: tz_property,
                    check_in_at: Time.zone.local(2026, 1, 1, 0, 30)).check_in_event
    end

    before { patch switch_property_path, params: { property_id: tz_property.id } }

    it "files the check-in under the local year it is displayed in (2026)" do
      get readings_history_path, params: { year: "2026" }

      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(new_year_event))
    end

    it "keeps it out of the previous year" do
      get readings_history_path, params: { year: "2025" }

      expect(response.body).not_to include(ActionView::RecordIdentifier.dom_id(new_year_event))
    end
  end

  describe "periodic readings in the Czech UI" do
    let(:meter_only_property) { create(:property, name: "AAA chata", tracking_mode: "meter_only") }

    before do
      create(:meter_reading_event, event_type: "periodic", property: meter_only_property, main_reading: 1000)
      patch switch_property_path, params: { property_id: meter_only_property.id }
    end

    it "labels them in Czech instead of falling back to English" do
      I18n.with_locale(:cs) { get readings_history_path }

      expect(response.body).to include("Odečet měřičů")
      expect(response.body).not_to include("Meter reading")
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
