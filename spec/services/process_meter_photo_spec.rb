# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessMeterPhoto do
  let(:property) { create(:property) }
  let!(:meter) { create(:meter, :main_vt, property: property) }
  let(:detection) do
    MeterPhotoDetection.create!(property: property, session_id: "s-1", status: :processing).tap do |det|
      det.photo.attach(io: file_fixture("meter.png").open, filename: "meter.png")
    end
  end

  def outcome(result)
    instance_double(ActiveInteraction::Base, valid?: true, result: result)
  end

  before do
    allow(GoogleVisionOcr).to receive(:run).and_return(outcome({ text: "12345 kWh" }))
    allow(ClassifyMeterImage).to receive(:run).and_return(outcome({ "is_meter" => true, "confidence" => 0.9 }))
  end

  context "the display is unreadable, so the matcher drops every number and returns no readings" do
    before { allow(MatchMeterReading).to receive(:run).and_return(outcome([])) }

    it "keeps the photo as a low-confidence card without a meter, so the user can assign it by hand" do
      result = described_class.run(detection: detection)

      expect(result).to be_valid
      expect(result.result).to eq([ detection ])
      expect(detection.reload).to have_attributes(
        status: "low_confidence", meter_id: nil, detected_value: nil, error_message: nil
      )
    end
  end

  context "the matcher finds one confident reading" do
    before do
      allow(MatchMeterReading).to receive(:run)
        .and_return(outcome([ { "meter_id" => meter.id, "reading_value" => 12_345, "confidence" => 0.9 } ]))
    end

    it "assigns the meter and value so the dashboard can prefill it" do
      described_class.run(detection: detection)

      expect(detection.reload).to have_attributes(status: "detected", meter_id: meter.id, detected_value: 12_345)
    end
  end
end
