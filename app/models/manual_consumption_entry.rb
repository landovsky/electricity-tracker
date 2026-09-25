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

  # C8 (soft warning against period consumption) is computed by
  # CreateManualConsumptionEntry#consumption_warning after the entry is saved.
end
