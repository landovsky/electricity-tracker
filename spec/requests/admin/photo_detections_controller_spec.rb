# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PhotoDetectionsController, type: :request do
  let(:property) { create(:property) }

  before { patch switch_property_path, params: { property_id: property.id } }

  def detection_with_photo(fixture:, filename:)
    MeterPhotoDetection.create!(property: property, session_id: "s-1", status: :error).tap do |d|
      d.photo.attach(io: file_fixture(fixture).open, filename: filename)
    end
  end

  describe "GET /admin/detekce" do
    context "a legacy SVG photo was stored before uploads were validated" do
      before { detection_with_photo(fixture: "meter.svg", filename: "legacy-meter.svg") }

      it "still lists detections and links the original file, since an SVG cannot be resized into a preview" do
        get admin_photo_detections_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("legacy-meter.svg")
        expect(response.body).not_to include("/representations/")
      end
    end

    context "a regular photo was uploaded" do
      before { detection_with_photo(fixture: "meter.png", filename: "meter.png") }

      it "links the medium variant so the admin does not download the full-size original" do
        get admin_photo_detections_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("/representations/")
      end
    end
  end
end
