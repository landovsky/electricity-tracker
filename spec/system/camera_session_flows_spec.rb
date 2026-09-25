# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Camera session page", type: :system, js: true do
  let!(:property) { create(:property) }
  let!(:vt_meter) { create(:meter, :main_vt, property: property) }
  let!(:nt_meter) { create(:meter, :main_nt, property: property) }

  def create_unassigned_detection(session_id)
    MeterPhotoDetection.create!(
      property: property, session_id: session_id,
      status: :low_confidence, confidence: 0.4, detected_value: 1234
    )
  end

  context "a crafted link carries HTML in the session id and event_type" do
    let(:session_id) { %(x"><img src=x onerror="__xss=1">) }

    before { create_unassigned_detection(session_id) }

    it "builds the continue link as plain text, so the payload never executes in the app origin" do
      visit camera_session_path(session_id, event_type: %("><img src=x onerror="__xss=2">))

      # Tag the server-rendered link so we can wait for the JS re-render of the bottom bar
      page.execute_script("document.querySelector(\"[data-camera-session-target='continueBtn']\").dataset.serverRendered = '1'")
      find("select[data-detection-id]").select(vt_meter.label)
      expect(page).to have_no_css("a[data-server-rendered]")

      link = find("a[data-camera-session-target='continueBtn']")
      expect(page.evaluate_script("window.__xss")).to be_nil
      expect(page).to have_no_css("[data-camera-session-target='bottomBar'] img")
      uri = URI.parse(link[:href])
      expect(Rack::Utils.parse_query(uri.query)).to eq("camera_session_id" => session_id, "event_type" => "check_in")
    end
  end

  context "the server rejects a meter reassignment (the meter was removed in another tab)" do
    before { create_unassigned_detection("sess-1") }

    it "rolls the select back and tells the user, instead of turning green as if it were saved" do
      visit camera_session_path("sess-1")
      vt_meter.discard

      # The app renders in its default Czech locale
      accept_alert(I18n.t("camera_sessions.reassign_failed", locale: :cs)) do
        find("select[data-detection-id]").select(vt_meter.label)
      end

      select = find("select[data-detection-id]")
      expect(select.value).to eq("")
      expect(select[:class]).not_to include("border-emerald-300")
      expect(MeterPhotoDetection.last.meter_id).to be_nil
    end
  end

  context "the user assigns a meter to an unmatched photo" do
    before { create_unassigned_detection("sess-2") }

    it "shows the saved choice and enables the continue button" do
      visit camera_session_path("sess-2")

      find("select[data-detection-id]").select(nt_meter.label)

      expect(page).to have_css("select[data-saved-meter-id='#{nt_meter.id}'].border-emerald-300")
      expect(page).to have_css("a[data-camera-session-target='continueBtn']")
      expect(MeterPhotoDetection.last.meter).to eq(nt_meter)
    end
  end
end
