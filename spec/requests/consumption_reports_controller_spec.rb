# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConsumptionReportsController, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:property) { create(:property) }
  let!(:main_meter) { create(:meter, property: property, meter_type: :main) }
  let!(:visitor) { create(:visitor, property: property) }

  before do
    property # ensure property exists
    user
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
          end_date: Date.new(2026, 12, 31)
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
          end_date: Date.new(2026, 2, 15)
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

    context "a guest who shared the house was archived after departure (E10)" do
      let(:guest) { create(:visitor, name: "Guest", status: :archived, property: property) }

      before do
        stay = create(:stay, :closed, visitor: visitor, property: property,
          check_in_at: Time.zone.local(2026, 3, 1, 12), check_out_at: Time.zone.local(2026, 3, 11, 12),
          main_reading_in: 1000.0, main_reading_out: 1200.0, recorded_by: user)
        create(:stay, visitor: guest, property: property, check_in_event: stay.check_in_event,
          check_out_event: stay.check_out_event)
      end

      it "still shows the guest's half in the default report instead of moving it onto the remaining visitor" do
        get consumption_reports_path, params: { year: 2026 }

        report = controller.instance_variable_get(:@report)
        totals = report[:visitors].to_h { |row| [ row[:visitor], row[:total_kwh] ] }
        expect(totals).to eq(visitor => 100.0, guest => 100.0)
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

    context "a hand-crafted URL sends dates as arrays or garbage" do
      it "redirects with the invalid-date message for an array year instead of a 500" do
        get consumption_reports_path, params: { year: [ "2025" ] }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("Invalid date format")
      end

      it "redirects with the invalid-date message for an array start date instead of a 500" do
        get consumption_reports_path, params: { start_date: [ "2025-01-01" ], end_date: "2025-02-01" }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("Invalid date format")
      end

      it "rejects a non-numeric year instead of silently reporting year 0" do
        get consumption_reports_path, params: { year: "abc" }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("Invalid date format")
      end
    end

    context "someone opens 'All time' just after midnight Prague time on a UTC server" do
      around do |example|
        original_tz = ENV["TZ"]
        ENV["TZ"] = "UTC"
        travel_to(Time.zone.local(2026, 9, 26, 0, 35)) { example.run }
      ensure
        ENV["TZ"] = original_tz
      end

      it "ends the range today in Prague, so a check-out recorded at 00:30 is included" do
        create(:stay, :closed, visitor: visitor, property: property,
          check_in_at: Time.zone.local(2026, 9, 20, 12), check_out_at: Time.zone.local(2026, 9, 26, 0, 30),
          main_reading_in: 1000.0, main_reading_out: 1080.0, recorded_by: user)

        get consumption_reports_path, params: { year: "all" }

        expect(controller.instance_variable_get(:@end_date)).to eq(Date.new(2026, 9, 26))
        expect(controller.instance_variable_get(:@report)[:total_consumption_kwh]).to eq(80.0)
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
        get consumption_reports_path, params: { year: Date.current.year }
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
