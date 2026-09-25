# frozen_string_literal: true

class CameraSessionsController < ApplicationController
  EVENT_TYPES = %w[check_in check_out].freeze
  MAX_PHOTO_SIZE = 15.megabytes

  def show
    @property = current_property
    @session_id = params[:id]
    @event_type = EVENT_TYPES.include?(params[:event_type]) ? params[:event_type] : "check_in"
    @visitor_name = params[:visitor_name] || ""
    @meters = @property.meters.kept.order(:meter_type, :meter_group, :label)
    @detections = session_detections.order(:created_at)
  end

  def upload
    @property = current_property
    @session_id = params[:id]
    @meters = @property.meters.kept.order(:meter_type, :meter_group, :label)

    photo_error = validate_photo(params[:photo])
    return render(plain: photo_error, status: :unprocessable_content) if photo_error

    detection = MeterPhotoDetection.create!(
      property: @property,
      session_id: @session_id,
      status: :processing
    )
    detection.photo.attach(params[:photo])

    outcome = ProcessMeterPhoto.run(detection: detection)
    result_detections = outcome.valid? ? Array(outcome.result) : [ detection.reload ]

    @detections_with_positions = result_detections.map do |det|
      det.reload
      [ det, position_of(det) ]
    end
    @usable_count = session_detections.usable.count
    @replaced_ids = result_detections.flat_map { |det| find_replaced_ids(det) }.uniq

    respond_to do |format|
      format.turbo_stream
    end
  end

  # The user explicitly picks the meter a photo shows. Their choice beats any
  # confidence score, so every other active detection for that meter in the
  # session is marked replaced — otherwise two readings would compete for the
  # same meter and the dashboard prefill would silently pick the newer one.
  def reassign
    @session_id = params[:id]
    @meters = current_property.meters.kept.order(:meter_type, :meter_group, :label)
    detection = session_detections.usable.find(params[:detection_id])
    meter = current_property.meters.kept.find(params[:meter_id])

    replaced = []
    MeterPhotoDetection.transaction do
      replaced = session_detections.active
        .where(meter_id: meter.id)
        .where.not(id: detection.id)
        .to_a
      replaced.each { |dup| dup.update!(status: :replaced) }
      detection.update!(meter: meter)
    end

    @changed_with_positions = [ detection, *replaced ].map { |det| [ det.reload, position_of(det) ] }
    @usable_count = session_detections.usable.count

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def session_detections
    current_property.meter_photo_detections.for_session(@session_id)
  end

  def position_of(detection)
    session_detections.where("id <= ?", detection.id).count
  end

  # Only images ActiveStorage can resize are accepted: detection cards always
  # render thumbnail variants, and an invariable blob (SVG, PDF, ...) would
  # make every render of the session page fail. The content type is sniffed
  # from the file itself, the same way ActiveStorage identifies it on attach.
  def validate_photo(photo)
    return t("camera_sessions.upload_errors.missing") unless photo.respond_to?(:tempfile)
    return t("camera_sessions.upload_errors.too_large", max_mb: MAX_PHOTO_SIZE / 1.megabyte) if photo.size > MAX_PHOTO_SIZE

    content_type = Marcel::MimeType.for(Pathname.new(photo.path), name: photo.original_filename, declared_type: photo.content_type)
    t("camera_sessions.upload_errors.not_image") unless ActiveStorage.variable_content_types.include?(content_type)
  end

  def find_replaced_ids(detection)
    return [] unless detection.meter_id.present?

    session_detections
      .where(meter_id: detection.meter_id, status: :replaced)
      .pluck(:id)
  end
end
