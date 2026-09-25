# frozen_string_literal: true

require "rails_helper"

RSpec.describe PeriodicReadingsController, type: :request do
  let!(:property) { create(:property, tracking_mode: :meter_only) }
  let!(:vt) { create(:meter, property: property, meter_type: :main, label: "VT") }
  let!(:nt) { create(:meter, property: property, meter_type: :main, label: "NT") }
  let(:user) { create(:user) }

  before do
    event = create(:meter_reading_event, event_type: :periodic, recorded_at: 2.days.ago, recorded_by_user: user)
    create(:meter_reading, meter_reading_event: event, meter: vt, value_kwh: 1000)
    create(:meter_reading, meter_reading_event: event, meter: nt, value_kwh: 500)
  end

  describe "POST /odecty-mericu" do
    context "VT is typed correctly but NT is typed below its previous reading" do
      let(:params) do
        { recorded_at: Time.current.iso8601, meter_readings: { vt.id.to_s => "1100", nt.id.to_s => "450" } }
      end

      it "rejects the whole reading, so no half-saved event becomes a boundary in the trends" do
        expect {
          post periodic_readings_path, params: params
        }.not_to change(MeterReadingEvent, :count)

        expect(MeterReading.count).to eq(2)
        expect(flash[:alert]).to include("NT")
      end
    end

    context "a Turbo submit is rejected because NT is typed below its previous reading" do
      def form_frame(body)
        body[/<turbo-stream action="replace" target="periodic-reading-form">.*?<\/turbo-stream>/m]
      end

      it "leaves the form untouched, so the valid VT value and the rest of the input survive and only NT needs retyping" do
        post periodic_readings_path,
             params: { recorded_at: Time.current.iso8601, meter_readings: { vt.id.to_s => "1100", nt.id.to_s => "450" } },
             as: :turbo_stream

        expect(response.body).to include("toast-container")
        expect(form_frame(response.body)).to be_nil
      end

      it "still resets the form once the reading is recorded" do
        post periodic_readings_path,
             params: { recorded_at: Time.current.iso8601, meter_readings: { vt.id.to_s => "1100", nt.id.to_s => "520" } },
             as: :turbo_stream

        expect(form_frame(response.body)).to be_present
      end
    end

    context "both meters are read correctly" do
      it "records one event with both readings" do
        expect {
          post periodic_readings_path, params: { recorded_at: Time.current.iso8601, meter_readings: { vt.id.to_s => "1100", nt.id.to_s => "520" } }
        }.to change(MeterReadingEvent, :count).by(1).and change(MeterReading, :count).by(2)
      end
    end
  end
end
