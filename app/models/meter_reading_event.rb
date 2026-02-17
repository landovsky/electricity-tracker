class MeterReadingEvent < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at
  audited

  # Enums
  enum :event_type, { check_in: "check_in", check_out: "check_out" }, validate: true

  # Associations
  belongs_to :recorded_by_user, class_name: "User", optional: true
  has_many :meter_readings, dependent: :destroy
  has_one :stay_as_check_in, class_name: "Stay", foreign_key: :check_in_event_id, dependent: :nullify
  has_one :stay_as_check_out, class_name: "Stay", foreign_key: :check_out_event_id, dependent: :nullify

  # Validations
  validates :recorded_at, presence: true
  validates :event_type, presence: true
  validate :chronological_consistency
  validate :main_meter_reading_required

  # Scopes
  scope :recent, -> { order(recorded_at: :desc) }
  scope :chronological, -> { order(recorded_at: :asc) }

  # Helper methods
  def visitor
    stay&.visitor
  end

  def stay
    stay_as_check_in || stay_as_check_out
  end

  private

  # C6: Event timestamps must be chronologically consistent with prior events
  def chronological_consistency
    return unless recorded_at.present?

    # Find the most recent event before this one
    previous_event = MeterReadingEvent.kept
                                      .where("recorded_at < ?", recorded_at)
                                      .where.not(id: id)
                                      .order(recorded_at: :desc)
                                      .first

    if previous_event && recorded_at < previous_event.recorded_at
      errors.add(:recorded_at, "must be after or equal to the previous event (#{previous_event.recorded_at})")
    end
  end

  # C4: Main meter reading is required on every event
  def main_meter_reading_required
    return if new_record? && meter_readings.empty?

    main_reading = meter_readings.find { |mr| mr.meter&.main? }
    errors.add(:base, "Main meter reading is required") unless main_reading
  end
end
