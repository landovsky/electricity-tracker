class Property < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Associations
  has_many :meters, dependent: :destroy
  has_many :stays, dependent: :destroy
  has_many :manual_consumption_entries, dependent: :destroy
  has_many :meter_photo_detections, dependent: :destroy
  has_many :property_users, dependent: :destroy
  has_many :users, through: :property_users

  # Validations
  validates :name, presence: true

  # Visitors with open stays at this property
  def current_visitors
    Visitor.kept
           .joins(:stays)
           .where(stays: { check_out_event_id: nil, property_id: id })
           .distinct
           .order(:name)
  end
end
