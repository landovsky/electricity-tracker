# frozen_string_literal: true

# Orchestrates the full meter photo processing pipeline:
#   1. Download image from ActiveStorage
#   2. OCR via Google Vision API
#   3. Classify: is it a meter photo?
#   4. Match meter(s) + extract reading(s)
#   5. Update the MeterPhotoDetection record(s)
#
# When multiple readings are found in a single image, additional
# MeterPhotoDetection records are created sharing the same session.
#
# Usage:
#   detection = MeterPhotoDetection.create!(property: property, session_id: SecureRandom.uuid)
#   detection.photo.attach(io: File.open("meter.jpg"), filename: "meter.jpg")
#   outcome = ProcessMeterPhoto.run(detection: detection)
#   outcome.result # => [detection, ...] (array of all detections from this photo)
class ProcessMeterPhoto < ApplicationService
  object :detection, class: MeterPhotoDetection

  HIGH_CONFIDENCE_THRESHOLD = 0.7

  def execute
    image_data = detection.photo.download

    # Step 1: OCR
    ocr_result = run_ocr(image_data)
    return if errors.any?

    ocr_text = ocr_result[:text]
    detection.update!(raw_ocr_text: ocr_text)

    # Step 2: Classify — is this a meter photo?
    classification = run_classification(ocr_text)
    return if errors.any?

    unless classification["is_meter"]
      detection.update!(
        status: :not_meter,
        confidence: classification["confidence"],
        error_message: classification["explanation"],
        llm_response: classification
      )
      return [detection]
    end

    # Step 3: Match meter(s) and extract reading(s)
    matches = run_matching(ocr_text)
    return if errors.any?

    # Step 4: Create detections for each match
    detections = build_detections(matches)

    # Step 5: Handle duplicates within session
    detections.each { |d| handle_session_duplicates(d) }

    detections
  rescue StandardError => e
    Rails.logger.error("ProcessMeterPhoto failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
    detection.update!(status: :error, error_message: e.message)
    errors.add(:base, "Pipeline failed: #{e.message}")
    nil
  end

  private

  def run_ocr(image_data)
    outcome = GoogleVisionOcr.run(image_data: image_data)
    unless outcome.valid?
      detection.update!(status: :error, error_message: outcome.errors.full_messages.join(", "))
      merge_errors!(outcome.errors)
      return nil
    end
    outcome.result
  end

  def run_classification(ocr_text)
    outcome = ClassifyMeterImage.run(ocr_text: ocr_text)
    unless outcome.valid?
      detection.update!(status: :error, error_message: outcome.errors.full_messages.join(", "))
      merge_errors!(outcome.errors)
      return nil
    end
    outcome.result
  end

  def run_matching(ocr_text)
    meters = detection.property.meters.kept
    outcome = MatchMeterReading.run(ocr_text: ocr_text, meters: meters)
    unless outcome.valid?
      detection.update!(status: :error, error_message: outcome.errors.full_messages.join(", "))
      merge_errors!(outcome.errors)
      return nil
    end
    outcome.result
  end

  def build_detections(matches)
    return [update_single_detection(matches.first)] if matches.size <= 1

    detections = []

    matches.each_with_index do |match, index|
      det = if index == 0
        detection
      else
        create_sibling_detection
      end

      apply_match(det, match)
      detections << det
    end

    detections
  end

  def update_single_detection(match)
    apply_match(detection, match)
    detection
  end

  def create_sibling_detection
    sibling = MeterPhotoDetection.create!(
      property: detection.property,
      session_id: detection.session_id,
      status: :processing,
      raw_ocr_text: detection.raw_ocr_text
    )
    sibling.photo.attach(detection.photo.blob)
    sibling
  end

  def apply_match(det, match)
    meter = find_meter(match["meter_id"])
    confidence = match["confidence"]&.to_f || 0.0
    reading_value = match["reading_value"]&.to_f

    status = if meter && confidence >= HIGH_CONFIDENCE_THRESHOLD
      :detected
    else
      :low_confidence
    end

    det.update!(
      meter: meter,
      detected_value: reading_value,
      confidence: confidence,
      status: status,
      llm_response: match
    )
  end

  def find_meter(meter_id)
    return nil if meter_id.blank?

    detection.property.meters.kept.find_by(id: meter_id)
  end

  def handle_session_duplicates(det)
    return unless det.meter_id.present?

    duplicates = MeterPhotoDetection
      .for_session(det.session_id)
      .where(meter_id: det.meter_id)
      .where.not(id: det.id)
      .where.not(status: :replaced)

    duplicates.each do |dup|
      if (dup.confidence || 0) <= (det.confidence || 0)
        dup.update!(status: :replaced)
      else
        det.update!(status: :replaced)
        break
      end
    end
  end

  def merge_errors!(other_errors)
    other_errors.each do |error|
      errors.add(error.attribute, error.message)
    end
  end
end
