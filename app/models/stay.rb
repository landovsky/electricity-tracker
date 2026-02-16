class Stay < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at
  audited

  # Associations
  belongs_to :visitor
  belongs_to :property
  belongs_to :check_in_event, class_name: "MeterReadingEvent", optional: true
  belongs_to :check_out_event, class_name: "MeterReadingEvent", optional: true

  # Validations
  validates :visitor_id, presence: true
  validates :property_id, presence: true
  validate :visitor_has_no_other_open_stay
  validate :check_out_reading_gte_check_in_reading

  # Scopes
  scope :open, -> { where(check_out_event_id: nil) }
  scope :closed, -> { where.not(check_out_event_id: nil) }

  # Computed properties
  def status
    check_out_event_id.nil? ? "open" : "closed"
  end

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  private

  # C2: A visitor can have at most one open stay at a time
  def visitor_has_no_other_open_stay
    return unless visitor_id.present?

    other_open_stays = Stay.kept
                           .where(visitor_id: visitor_id, check_out_event_id: nil)
                           .where.not(id: id)

    if other_open_stays.exists?
      errors.add(:base, "Visitor already has an open stay")
    end
  end

  # C3: Check-out reading >= check-in reading (per meter)
  def check_out_reading_gte_check_in_reading
    return unless check_in_event && check_out_event

    check_in_event.meter_readings.each do |check_in_reading|
      check_out_reading = check_out_event.meter_readings.find_by(meter_id: check_in_reading.meter_id)

      next unless check_out_reading

      if check_out_reading.value_kwh < check_in_reading.value_kwh
        errors.add(:base, "Check-out reading for #{check_in_reading.meter.label} (#{check_out_reading.value_kwh} kWh) must be >= check-in reading (#{check_in_reading.value_kwh} kWh)")
      end
    end
  end
end
