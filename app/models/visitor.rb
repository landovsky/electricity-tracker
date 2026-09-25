class Visitor < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  # Enums
  enum :status, { active: "active", archived: "archived" }, validate: true

  # Associations
  belongs_to :property
  has_many :stays, dependent: :destroy
  has_many :manual_consumption_entries, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :status, presence: true

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :archived, -> { where(status: "archived") }

  # The open stay that makes this visitor "currently here". Works on preloaded
  # stays and skips discarded or orphaned (check-in deleted) stays.
  def current_stay
    stays.find { |stay| stay.open? && stay.live? }
  end
end
