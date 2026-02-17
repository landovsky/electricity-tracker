class ManualConsumptionEntry < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at
  audited

  # Associations
  belongs_to :visitor
  belongs_to :property
  belongs_to :recorded_by_user, class_name: "User", optional: true

  # Validations
  validates :date, presence: true
  validates :kwh, presence: true, numericality: { greater_than: 0 }
  validates :note, presence: true

  # Scopes
  scope :recent, -> { order(date: :desc) }
  scope :for_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }

  # C8: Manual entry kWh should not exceed unattributed consumption in the enclosing period
  # This is a soft validation - returns a warning, not a hard error
  def exceeds_period_consumption?
    # This will be implemented in the allocation service layer
    # For now, return false
    false
  end

  def consumption_warning
    return nil unless exceeds_period_consumption?

    I18n.t("activerecord.errors.models.manual_consumption_entry.attributes.kwh.exceeds_period", kwh: kwh)
  end
end
