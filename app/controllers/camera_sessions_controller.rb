# frozen_string_literal: true

class CameraSessionsController < ApplicationController
  def show
    @property = current_property
    @session_id = params[:id]
    @event_type = params[:event_type] || "check_in"
    @visitor_name = params[:visitor_name] || ""
    @meters = @property.meters.kept.order(:meter_type, :meter_group, :label)
    @detections = MeterPhotoDetection.for_session(@session_id).order(:created_at)
  end

  def upload
    @property = current_property
    @session_id = params[:id]
    @meters = @property.meters.kept.order(:meter_type, :meter_group, :label)

    detection = MeterPhotoDetection.create!(
      property: @property,
      session_id: @session_id,
      status: :processing
    )
    detection.photo.attach(params[:photo])

    outcome = ProcessMeterPhoto.run(detection: detection)
    result_detections = outcome.valid? ? Array(outcome.result) : [detection.reload]

    @detections_with_positions = result_detections.map do |det|
      det.reload
      position = MeterPhotoDetection.for_session(@session_id).where("id <= ?", det.id).count
      [det, position]
    end
    @usable_count = MeterPhotoDetection.for_session(@session_id).usable.count
    @replaced_ids = result_detections.flat_map { |det| find_replaced_ids(det) }.uniq

    respond_to do |format|
      format.turbo_stream
    end
  end

  def reassign
    detection = MeterPhotoDetection.find(params[:detection_id])
    meter = current_property.meters.kept.find(params[:meter_id])
    detection.update!(meter: meter)

    head :ok
  end

  private

  def find_replaced_ids(detection)
    return [] unless detection.meter_id.present?

    MeterPhotoDetection
      .for_session(@session_id)
      .where(meter_id: detection.meter_id, status: :replaced)
      .pluck(:id)
  end
end
