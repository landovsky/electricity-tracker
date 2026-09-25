# frozen_string_literal: true

require "rails_helper"

RSpec.describe CameraSessionsController, type: :request do
  let(:property) { create(:property) }
  let!(:vt_meter) { create(:meter, :main_vt, property: property) }
  let!(:nt_meter) { create(:meter, :main_nt, property: property) }
  let(:session_id) { "session-#{SecureRandom.hex(4)}" }
  let(:turbo_stream) { { "Accept" => "text/vnd.turbo-stream.html" } }

  def detection_for(prop = property, sid: session_id, **attrs)
    MeterPhotoDetection.create!(
      { property: prop, session_id: sid, status: :low_confidence, confidence: 0.5, detected_value: 1234 }.merge(attrs)
    )
  end

  # The request selects its property from session[:property_id]; pin it to `property`.
  before { patch switch_property_path, params: { property_id: property.id } }

  describe "PATCH /foceni/:id/reassign" do
    context "another property's detection id is sent (ids are sequential and guessable)" do
      let(:other_property) { create(:property) }
      let!(:foreign_detection) { detection_for(other_property, sid: session_id) }

      it "returns 404 and leaves the foreign detection untouched, so no other household's camera prefill is corrupted" do
        patch reassign_camera_session_path(session_id),
              params: { detection_id: foreign_detection.id, meter_id: vt_meter.id }, headers: turbo_stream

        expect(response).to have_http_status(:not_found)
        expect(foreign_detection.reload.meter_id).to be_nil
      end
    end

    context "the detection belongs to a different camera session than the URL" do
      let!(:other_session_detection) { detection_for(sid: "some-other-session") }

      it "returns 404, so a card can only be reassigned from the session page that shows it" do
        patch reassign_camera_session_path(session_id),
              params: { detection_id: other_session_detection.id, meter_id: vt_meter.id }, headers: turbo_stream

        expect(response).to have_http_status(:not_found)
        expect(other_session_detection.reload.meter_id).to be_nil
      end
    end

    context "the user points an older photo at a meter a newer photo was auto-matched to" do
      let!(:older) { detection_for(meter: nil, detected_value: 1111) }
      let!(:newer) { detection_for(meter: vt_meter, status: :detected, confidence: 0.95, detected_value: 2222) }

      before do
        patch reassign_camera_session_path(session_id),
              params: { detection_id: older.id, meter_id: vt_meter.id }, headers: turbo_stream
      end

      it "marks the auto-matched photo replaced, because the user's explicit choice must win over confidence" do
        expect(response).to have_http_status(:ok)
        expect(older.reload.meter).to eq(vt_meter)
        expect(newer.reload).to be_replaced
      end

      it "leaves exactly one usable reading for the meter, so the dashboard prefills the value the user picked" do
        usable = MeterPhotoDetection.for_session(session_id).usable.where(meter: vt_meter)
        expect(usable.pluck(:detected_value)).to eq([ 1111 ])
      end

      it "re-renders both cards and the usable count so the page shows the conflict was resolved" do
        expect(response.body).to include(%(target="detection-#{older.id}"))
        expect(response.body).to include(%(target="detection-#{newer.id}"))
        expect(response.body).to match(/id="detection-#{newer.id}" class="[^"]*opacity-50/)
        expect(response.body).to match(%r{id="usable-count"[^>]*>1</span>})
      end
    end

    context "the reassigned photo already holds a different meter than the other photo" do
      let!(:photo_on_nt) { detection_for(meter: nt_meter, status: :detected, confidence: 0.9) }
      let!(:photo_to_move) { detection_for(meter: nil) }

      it "does not touch readings of other meters" do
        patch reassign_camera_session_path(session_id),
              params: { detection_id: photo_to_move.id, meter_id: vt_meter.id }, headers: turbo_stream

        expect(photo_on_nt.reload).to be_detected
      end
    end

    context "a group has VT and NT meters whose labels differ only by tariff" do
      let!(:detection) { detection_for(meter: nil) }

      def meter_option_order(body)
        body.scan(/<option[^>]*value="(#{vt_meter.id}|#{nt_meter.id})"/).flatten.first(2)
      end

      it "re-renders the card with the session page's VT-before-NT order, so a reassigned card never swaps the tariffs" do
        get camera_session_path(session_id)
        show_order = meter_option_order(response.body)

        patch reassign_camera_session_path(session_id),
              params: { detection_id: detection.id, meter_id: nt_meter.id }, headers: turbo_stream

        expect(show_order).to eq([ vt_meter.id.to_s, nt_meter.id.to_s ])
        expect(meter_option_order(response.body)).to eq(show_order)
      end
    end

    context "a replaced card is sent (its select is hidden, only a crafted request can do this)" do
      let!(:replaced) { detection_for(status: :replaced) }

      it "returns 404 instead of reviving a discarded reading next to the active one" do
        patch reassign_camera_session_path(session_id),
              params: { detection_id: replaced.id, meter_id: vt_meter.id }, headers: turbo_stream

        expect(response).to have_http_status(:not_found)
        expect(replaced.reload.meter_id).to be_nil
      end
    end
  end

  describe "GET /foceni/:id" do
    context "another property's detections share the session id" do
      let(:other_property) { create(:property) }

      before { detection_for(other_property, detected_value: 987_654) }

      it "does not show them, so a session id never leaks another household's readings" do
        get camera_session_path(session_id)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("987 654")
      end
    end

    context "a crafted event_type tries to inject markup into the page's data attributes" do
      it "falls back to check_in so the value handed to the Stimulus controller is always a known one" do
        get camera_session_path(session_id), params: { event_type: %("><img src=x onerror=alert(1)>) }

        expect(response.body).to include(%(data-camera-session-event-type-value="check_in"))
        expect(response.body).not_to include("onerror=alert")
      end
    end

    context "an SVG was stored before uploads were validated" do
      before do
        detection = detection_for(status: :error)
        detection.photo.attach(io: file_fixture("meter.svg").open, filename: "meter.svg")
      end

      it "still renders the session page instead of failing on the thumbnail variant" do
        get camera_session_path(session_id)

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST /foceni/:id/upload" do
    context "a phone camera photo is uploaded" do
      before do
        allow(ProcessMeterPhoto).to receive(:run) do |detection:|
          detection.update!(status: :detected, meter: vt_meter, confidence: 0.9, detected_value: 4321)
          instance_double(ActiveInteraction::Base, valid?: true, result: [ detection ])
        end
      end

      it "creates a detection and renders its card" do
        expect {
          post upload_camera_session_path(session_id),
               params: { photo: fixture_file_upload("meter.png", "image/png") }, headers: turbo_stream
        }.to change(MeterPhotoDetection, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("4 321")
      end
    end

    context "a non-image file (SVG) is posted, bypassing the image/* file picker hint" do
      it "rejects it with 422 and a Czech reason before anything is stored, so the session page keeps rendering" do
        allow(ProcessMeterPhoto).to receive(:run)

        expect {
          post upload_camera_session_path(session_id),
               params: { photo: fixture_file_upload("meter.svg", "image/svg+xml") }, headers: turbo_stream
        }.not_to change(MeterPhotoDetection, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to eq(I18n.t("camera_sessions.upload_errors.not_image"))
        expect(ProcessMeterPhoto).not_to have_received(:run)
      end
    end

    context "an SVG is disguised with a .png name and image/png content type" do
      it "still rejects it, because the type is sniffed from the file content" do
        post upload_camera_session_path(session_id),
             params: { photo: Rack::Test::UploadedFile.new(file_fixture("meter.svg"), "image/png", original_filename: "meter.png") },
             headers: turbo_stream

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "the photo exceeds the size limit (whole file is held in memory and Base64-encoded for OCR)" do
      it "rejects it with 422 before downloading it into the pipeline" do
        stub_const("CameraSessionsController::MAX_PHOTO_SIZE", 10.bytes)
        allow(ProcessMeterPhoto).to receive(:run)

        post upload_camera_session_path(session_id),
             params: { photo: fixture_file_upload("meter.png", "image/png") }, headers: turbo_stream

        expect(response).to have_http_status(:unprocessable_content)
        expect(ProcessMeterPhoto).not_to have_received(:run)
      end
    end

    context "the request carries no photo at all" do
      it "rejects it with 422 instead of creating an empty detection" do
        expect {
          post upload_camera_session_path(session_id), headers: turbo_stream
        }.not_to change(MeterPhotoDetection, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
