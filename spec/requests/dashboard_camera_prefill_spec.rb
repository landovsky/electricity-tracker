# frozen_string_literal: true

require "rails_helper"

# After a camera session the phone redirects to /?camera_session_id=<id>; the
# dashboard then shows the session's photos next to the check-in/out forms
# and prefills the detected readings.
RSpec.describe "Dashboard camera prefill", type: :request do
  let(:property) { create(:property, name: "Suchá") }
  let!(:meter) { create(:meter, :main, property: property) }
  let!(:visitor) { create(:visitor, property: property) }
  let(:session_id) { "session-#{SecureRandom.hex(4)}" }

  def detection_with_photo(prop:, meter:, fixture:, filename:, value:)
    MeterPhotoDetection.create!(
      property: prop, meter: meter, session_id: session_id,
      status: :detected, confidence: 0.95, detected_value: value
    ).tap { |d| d.photo.attach(io: file_fixture(fixture).open, filename: filename) }
  end

  before { patch switch_property_path, params: { property_id: property.id } }

  context "another property's camera session shares the session id (shared URL or property switch mid-flow)" do
    let(:other_property) { create(:property, name: "Tymlova") }
    let(:other_meter) { create(:meter, :main, property: other_property) }

    before do
      detection_with_photo(prop: other_property, meter: other_meter, fixture: "meter.png",
                           filename: "foreign-meter.png", value: 55_555)
      detection_with_photo(prop: property, meter: meter, fixture: "meter.png",
                           filename: "own-meter.png", value: 12_345)
    end

    it "shows only the current property's photos, so a session id never exposes another household's meter photos" do
      get root_path(camera_session_id: session_id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("own-meter.png")
      expect(response.body).not_to include("foreign-meter.png")
    end

    it "prefills only readings detected for this property" do
      get root_path(camera_session_id: session_id)

      expect(response.body).to include('value="12345.0"')
      expect(response.body).not_to include("55555")
    end
  end

  context "a legacy SVG photo was stored before uploads were validated" do
    before do
      detection_with_photo(prop: property, meter: meter, fixture: "meter.svg",
                           filename: "legacy-meter.svg", value: 12_345)
    end

    it "still renders the check-in form with the raw photo link instead of failing on the thumbnail variant" do
      get root_path(camera_session_id: session_id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("legacy-meter.svg")
      expect(response.body).to include('value="12345.0"')
    end
  end
end
