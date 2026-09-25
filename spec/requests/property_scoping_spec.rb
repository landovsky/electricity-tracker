# frozen_string_literal: true

require "rails_helper"

# Members may only act on properties they belong to (PropertyUser), further
# narrowed by the request subdomain. Record ids are sequential and guessable,
# so every lookup by id must go through the user's reachable properties.
RSpec.describe "Property scoping of stays, manual entries and visitors", type: :request do
  let(:own_property) { create(:property, name: "Suchá", subdomain: "sepot") }
  let(:foreign_property) { create(:property, name: "Tymlova", subdomain: "tymlova") }
  let!(:own_meter) { create(:meter, :main, property: own_property) }
  let!(:foreign_meter) { create(:meter, :main, property: foreign_property) }
  let(:own_visitor) { create(:visitor, name: "Babička", property: own_property) }
  let(:member) { create(:user, :member) }

  before do
    create(:property_user, user: member, property: own_property)
    sign_in_as(member)
    host! "sepot.example.com"
  end

  describe "PATCH /pobyty/:id/check_out" do
    context "a member guesses the id of a stay in a property they do not belong to" do
      let!(:foreign_stay) do
        create(:stay, visitor: create(:visitor, property: foreign_property), property: foreign_property,
                      main_reading_in: 1000.0)
      end

      it "refuses, so the other property's stay stays open and its meters get no reading" do
        expect {
          patch check_out_stay_path(foreign_stay), params: { meter_readings: { foreign_meter.id => 2000 } }
        }.not_to change(MeterReadingEvent, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("stays.not_found"))
        expect(foreign_stay.reload).to be_open
      end
    end
  end

  describe "POST /pobyty (check-in)" do
    context "a member posts a property_id of a property they do not belong to" do
      it "refuses, so no stay or reading is written to the other property" do
        expect {
          post stays_path, params: {
            visitor_id: own_visitor.id, property_id: foreign_property.id,
            meter_readings: { foreign_meter.id => 5000 }
          }
        }.not_to change(MeterReadingEvent, :count)

        expect(Stay.where(property: foreign_property)).to be_empty
        expect(flash[:alert]).to be_present
      end
    end

    context "a Turbo request carries a property_id that does not exist" do
      it "answers with an error toast instead of crashing on a missing property" do
        post stays_path,
             params: { visitor_id: own_visitor.id, property_id: 999_999, meter_readings: { own_meter.id => 10 } },
             as: :turbo_stream

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("toast-container")
        expect(Stay.count).to eq(0)
      end
    end
  end

  describe "POST /rucni-spotreba (manual entry)" do
    context "a member posts a property_id of a property they do not belong to" do
      it "refuses, so the other property's shared pool is not reduced by this entry" do
        expect {
          post manual_consumption_entries_path, params: {
            visitor_id: own_visitor.id, property_id: foreign_property.id, kwh: 50, note: "EV"
          }
        }.not_to change(ManualConsumptionEntry, :count)
      end
    end

    context "the target property has been archived" do
      it "refuses, because archived properties are no longer bookable" do
        admin = create(:user, :admin)
        sign_in_as(admin)
        archived = create(:property, name: "Old house")
        archived_visitor = create(:visitor, property: archived)
        archived.discard

        expect {
          post manual_consumption_entries_path, params: {
            visitor_id: archived_visitor.id, property_id: archived.id, kwh: 50, note: "EV"
          }
        }.not_to change(ManualConsumptionEntry, :count)
      end
    end

    context "a Turbo request carries a property_id that does not exist" do
      it "answers with an error toast instead of a 500" do
        post manual_consumption_entries_path,
             params: { visitor_id: own_visitor.id, property_id: 999_999, kwh: 50, note: "EV" },
             as: :turbo_stream

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("toast-container")
      end
    end
  end

  # tymlova.kopernici.cz is served by the same deployment, but the member's
  # only property has subdomain "sepot", so they have no current property there.
  describe "a member opens the app on a host with none of their properties" do
    before { host! "tymlova.example.com" }

    it "redirects the visitors list to the dashboard's empty state instead of a 500" do
      get visitors_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("no_property"))
    end

    it "redirects the new-visitor form instead of a 500" do
      get new_visitor_path

      expect(response).to redirect_to(root_path)
    end

    it "redirects a check-in without writing anything" do
      expect {
        post stays_path, params: { visitor_id: own_visitor.id, meter_readings: { own_meter.id => 10 } }
      }.not_to change(MeterReadingEvent, :count)

      expect(response).to redirect_to(root_path)
    end

    it "redirects a manual entry without writing anything" do
      expect {
        post manual_consumption_entries_path, params: { visitor_id: own_visitor.id, kwh: 5, note: "EV" }
      }.not_to change(ManualConsumptionEntry, :count)

      expect(response).to redirect_to(root_path)
    end

    it "redirects a camera session instead of a 500" do
      get camera_session_path("abc")

      expect(response).to redirect_to(root_path)
    end

    it "still renders the dashboard, which owns the empty state" do
      get root_path

      expect(response).to have_http_status(:ok)
    end
  end
end
