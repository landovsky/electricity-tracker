class MeterReadingEvent < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at
  audited

  # Enums
  enum :event_type, { check_in: "check_in", check_out: "check_out", initial: "initial", periodic: "periodic" }, validate: true

  # Associations
  belongs_to :recorded_by_user, class_name: "User", optional: true
  has_many :meter_readings, dependent: :destroy
  has_one :stay_as_check_in, class_name: "Stay", foreign_key: :check_in_event_id, dependent: :nullify
  has_one :stay_as_check_out, class_name: "Stay", foreign_key: :check_out_event_id, dependent: :nullify

  # Validations
  validates :recorded_at, presence: true
  validates :event_type, presence: true
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

  # C4: Main meter reading is required on every event
  # With multi-tariff support, a reading is required for EACH main-type meter
  # Initial events (meter setup) are exempt — they record a single meter's starting value
  def main_meter_reading_required
    return if initial?
    return if new_record? && meter_readings.empty?

    main_reading = meter_readings.find { |mr| mr.meter&.main? }
    errors.add(:base, :main_meter_required) unless main_reading
  end
end
