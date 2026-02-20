# frozen_string_literal: true

class MeterPhotoDetection < ApplicationRecord
  enum :status, {
    processing:     "processing",
    detected:       "detected",
    low_confidence: "low_confidence",
    not_meter:      "not_meter",
    error:          "error",
    replaced:       "replaced"
  }, validate: true

  belongs_to :property
  belongs_to :meter, optional: true
  has_one_attached :photo

  scope :for_session, ->(sid) { where(session_id: sid) }
  scope :active, -> { where.not(status: :replaced) }
  scope :usable, -> { where(status: %i[detected low_confidence]) }
end
