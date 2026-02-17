# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConsumptionReportsController, type: :request do
  let(:user) { create(:user) }
  let(:property) { create(:property) }
  let!(:main_meter) { create(:meter, property: property, meter_type: :main) }
  let!(:visitor) { create(:visitor) }

  before do
    user
    property
  end

  describe "GET /consumption_reports (index)" do
    context "with year parameter" do
      it "returns success" do
        get consumption_reports_path, params: { year: 2026 }
        expect(response).to have_http_status(:success)
      end

      it "calls CalculateConsumption service with year range" do
        expect(CalculateConsumption).to receive(:run).with(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 12, 31),
          include_archived_visitors: false
        ).and_call_original

        get consumption_reports_path, params: { year: 2026 }
      end
    end

    context "with explicit date range parameters" do
      it "returns success" do
        get consumption_reports_path, params: {
          start_date: "2026-01-15",
          end_date: "2026-02-15"
        }
        expect(response).to have_http_status(:success)
      end

      it "calls CalculateConsumption service with explicit range" do
        expect(CalculateConsumption).to receive(:run).with(
          property: property,
          start_date: Date.new(2026, 1, 15),
          end_date: Date.new(2026, 2, 15),
          include_archived_visitors: false
        ).and_call_original

        get consumption_reports_path, params: {
          start_date: "2026-01-15",
          end_date: "2026-02-15"
        }
      end
    end

    context "without any parameters" do
      it "returns success with default to current year" do
        get consumption_reports_path
        expect(response).to have_http_status(:success)
      end
    end

    context "with include_archived parameter" do
      it "passes include_archived to service" do
        expect(CalculateConsumption).to receive(:run).with(
          property: property,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2026, 12, 31),
          include_archived_visitors: true
        ).and_call_original

        get consumption_reports_path, params: { year: 2026, include_archived: "true" }
      end
    end

    context "with invalid date format" do
      it "redirects to root with error" do
        get consumption_reports_path, params: {
          start_date: "invalid-date",
          end_date: "2026-02-15"
        }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("Invalid date format")
      end
    end

    context "when no property exists" do
      before do
        Property.destroy_all
      end

      it "redirects to root with error" do
        get consumption_reports_path, params: { year: 2026 }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("No property found")
      end
    end

    context "with actual consumption data" do
      let!(:stay) do
        create(:stay, :closed,
          visitor: visitor,
          property: property,
          check_in_at: 30.days.ago,
          check_out_at: 20.days.ago,
          main_reading_in: 1000.0,
          main_reading_out: 1250.0,
          recorded_by: user
        )
      end

      it "returns report with visitor consumption" do
        get consumption_reports_path, params: { year: Date.today.year }
        expect(response).to have_http_status(:success)
      end
    end

    context "when CalculateConsumption service returns errors" do
      before do
        allow(CalculateConsumption).to receive(:run).and_return(
          double(valid?: false, errors: double(full_messages: [ "Date range error" ]))
        )
      end

      it "displays error message" do
        get consumption_reports_path, params: { year: 2026 }
        expect(flash.now[:alert]).to eq("Date range error")
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
      get consumption_reports_path
      expect(response).to redirect_to(login_path)
    end
  end
end
