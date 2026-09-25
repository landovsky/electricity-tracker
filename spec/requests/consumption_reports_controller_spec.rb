# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConsumptionReportsController, type: :request do
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

  # Tailwind v4 only emits classes it finds verbatim in the source, so a class
  # assembled at runtime renders fine in HTML but has no CSS rule. CI builds
  # the stylesheet before running specs.
  def compiled_tailwind_css
    path = Rails.root.join("app/assets/builds/tailwind.css")
    raise "Run bin/rails tailwindcss:build before this spec" unless path.exist?

    path.read
  end

  def css_rule_for?(klass)
    compiled_tailwind_css.match?(/\.#{Regexp.escape(klass)}\s*\{/)
  end

  describe "per-visitor bars" do
    context "the report lists more visitors than the first four palette colours (production has 9 users)" do
      before do
        5.times { |i| create(:visitor, name: "Host #{i}", property: property) }
        property.visitors.order(:id).each_with_index do |v, i|
          create(:stay, :closed, visitor: v, property: property, recorded_by: user,
            check_in_at: Time.zone.local(2025, 3, 1 + (3 * i), 12), check_out_at: Time.zone.local(2025, 3, 2 + (3 * i), 12),
            main_reading_in: 1000 + (100 * i), secondary_reading_in: 500 + (100 * i),
            main_reading_out: 1050 + (100 * i), secondary_reading_out: 525 + (100 * i))
        end
      end

      it "gives every bar a background colour that actually exists in the compiled CSS, so none is invisible" do
        get consumption_reports_path, params: { year: 2025 }

        bars = Nokogiri::HTML(response.body).css("div.h-full.rounded-full")
        bar_colours = bars.map { |bar| bar["class"].split.find { |c| c.start_with?("bg-") } }

        expect(bar_colours.size).to eq(6)
        # Built dynamically on purpose: a literal here would itself make Tailwind
        # generate the classes and mask the bug.
        expect(bar_colours).to include(*%w[pink indigo].map { |hue| "bg-#{hue}-500" })
        expect(bar_colours.reject { |c| css_rule_for?(c) }).to be_empty
      end
    end
  end

  describe "meter-only trends page" do
    let(:property) { create(:property, tracking_mode: :meter_only) }

    def periodic_reading(at, value)
      event = create(:meter_reading_event, event_type: :periodic, recorded_at: at, recorded_by_user: user)
      create(:meter_reading, meter_reading_event: event, meter: main_meter, value_kwh: value)
    end

    context "the property has readings spanning two years" do
      before do
        periodic_reading(Time.zone.local(2024, 1, 1, 12), 1000)
        periodic_reading(Time.zone.local(2024, 2, 1, 12), 1100)
        periodic_reading(Time.zone.local(2025, 1, 1, 12), 2000)
        periodic_reading(Time.zone.local(2025, 2, 1, 12), 2150)
      end

      it "labels each monthly row with month and year, so February 2024 and February 2025 are distinguishable" do
        get consumption_reports_path, params: { year: "all" }

        expect(response.body).to include("February 2024", "February 2025")
        expect(response.body).not_to include("01. Feb")
      end

      it "lays out the year-over-year table with explicit columns, since no grid-cols-N class for it is generated" do
        get consumption_reports_path, params: { year: "all" }

        doc = Nokogiri::HTML(response.body)
        yoy_rows = doc.css("div.grid[style*='grid-template-columns']")
        expect(yoy_rows).not_to be_empty
        expect(yoy_rows.first["style"]).to include("repeat(9, minmax(0, 1fr))")

        grid_classes = doc.css("div.grid").flat_map { |d| d["class"].split.grep(/\Agrid-cols-/) }.uniq
        expect(grid_classes.reject { |c| css_rule_for?(c) }).to be_empty
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
