class Property < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Associations
  has_many :meters, dependent: :destroy
  has_many :stays, dependent: :destroy
  has_many :manual_consumption_entries, dependent: :destroy

  # Validations
  validates :name, presence: true
end
