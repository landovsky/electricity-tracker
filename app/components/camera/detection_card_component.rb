# frozen_string_literal: true

class Camera::DetectionCardComponent < ApplicationComponent
  def initialize(detection:, meters:, position:)
    @detection = detection
    @meters = meters
    @position = position
  end

  attr_reader :detection, :meters, :position

  delegate :status, :detected_value, :confidence, :error_message, :meter, to: :detection

  def card_classes
    base = "flex items-start gap-3 p-3 border-2 rounded-xl mb-2"
    case status
    when "detected"
      "#{base} border-emerald-200 bg-emerald-50"
    when "low_confidence"
      "#{base} border-amber-200 bg-amber-50"
    when "not_meter", "error"
      "#{base} border-red-200 bg-red-50"
    when "processing"
      "#{base} border-blue-200 bg-blue-50"
    when "replaced"
      "#{base} border-gray-200 bg-gray-50 opacity-50"
    else
      "#{base} border-gray-200"
    end
  end

  def thumb_classes
    base = "w-14 h-14 rounded-lg flex items-center justify-center text-white text-xs font-mono font-medium flex-shrink-0"
    case status
    when "detected"
      "#{base} bg-gradient-to-br from-slate-400 to-slate-600"
    when "low_confidence"
      "#{base} bg-gradient-to-br from-amber-300 to-amber-500"
    when "not_meter", "error"
      "#{base} bg-gradient-to-br from-red-300 to-red-500"
    when "processing"
      "#{base} bg-gradient-to-br from-blue-300 to-blue-500 animate-pulse"
    when "replaced"
      "#{base} bg-gradient-to-br from-gray-300 to-gray-400"
    end
  end

  def has_photo?
    detection.photo.attached?
  end

  def photo_url
    return nil unless has_photo?

    Rails.application.routes.url_helpers.rails_blob_path(detection.photo, only_path: true)
  end

  def thumb_url
    return nil unless has_photo?

    Rails.application.routes.url_helpers.rails_blob_path(
      detection.photo.variant(resize_to_fill: [ 112, 112 ]),
      only_path: true
    )
  end

  def status_icon
    case status
    when "detected" then '<span class="text-emerald-500">&#10003;</span>'
    when "low_confidence" then '<span class="text-amber-500">&#9888;</span>'
    when "not_meter", "error" then '<span class="text-red-500">&#10007;</span>'
    end
  end

  def meter_label
    base = case status
    when "detected", "low_confidence", "replaced"
      meter&.label || t("camera_sessions.detection.unknown_meter")
    when "not_meter"
      t("camera_sessions.detection.not_meter")
    when "error"
      t("camera_sessions.detection.error")
    else
      ""
    end

    if meter&.short_identifier.present? && status.in?(%w[ detected low_confidence replaced ])
      "#{base} · #{meter.short_identifier}"
    else
      base
    end
  end

  def reading_display
    return nil unless detected_value

    helpers.number_with_delimiter(detected_value, delimiter: " ")
  end

  def confidence_display
    return nil unless confidence

    "#{(confidence * 100).round}%"
  end

  def confidence_classes
    return "" unless confidence

    if confidence >= 0.8
      "text-emerald-600"
    elsif confidence >= 0.5
      "text-amber-600"
    else
      "text-red-600"
    end
  end

  def show_meter_select?
    status.in?(%w[detected low_confidence])
  end

  def meter_select_classes
    if detection.meter_id.present?
      "border-emerald-300 bg-emerald-50"
    else
      "border-amber-300 bg-amber-50"
    end
  end

  def dom_id
    "detection-#{detection.id}"
  end
end
