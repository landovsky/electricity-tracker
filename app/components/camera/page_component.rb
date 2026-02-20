# frozen_string_literal: true

class Camera::PageComponent < ApplicationComponent
  def initialize(event_type:, visitor_name:, session_id:, detections:, meters:)
    @event_type = event_type
    @visitor_name = visitor_name
    @session_id = session_id
    @detections = detections
    @meters = meters
  end

  attr_reader :event_type, :visitor_name, :session_id, :detections, :meters

  def check_in?
    event_type == "check_in"
  end

  def action_badge_classes
    if check_in?
      "bg-emerald-100 text-emerald-800"
    else
      "bg-amber-100 text-amber-800"
    end
  end

  def action_label
    if check_in?
      t("camera_sessions.badge_check_in")
    else
      t("camera_sessions.badge_check_out")
    end
  end

  def usable_count
    detections.select { |d| d.detected? || d.low_confidence? }.count
  end

  def has_detections?
    detections.any?
  end

  def upload_url
    upload_camera_session_path(session_id)
  end

  def reassign_url
    reassign_camera_session_path(session_id)
  end
end
