class Property < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Enums
  enum :tracking_mode, { visitors: "visitors", meter_only: "meter_only" }, validate: true

  # Associations
  has_many :meters, dependent: :destroy
  has_many :stays, dependent: :destroy
  has_many :manual_consumption_entries, dependent: :destroy
  has_many :meter_photo_detections, dependent: :destroy
  has_many :property_users, dependent: :destroy
  has_many :users, through: :property_users
  has_many :visitors, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :subdomain, allow_blank: true,
            format: { with: /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/, message: "only lowercase alphanumeric and hyphens" },
            if: :subdomain_changed?

  # Visitors with open stays at this property
  def current_visitors
    visitors.kept
            .joins(:stays)
            .where(stays: { check_out_event_id: nil, property_id: id })
            .distinct
            .order(:name)
  end
end
