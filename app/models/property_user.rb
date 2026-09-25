# frozen_string_literal: true

# Join model linking users to properties they are allowed to access.
# TODO: Replace checkbox UI with a scalable search/select when user count grows.
class PropertyUser < ApplicationRecord
  belongs_to :property
  belongs_to :user

  validates :property_id, uniqueness: { scope: :user_id }

  after_create :create_visitor_for_user

  private

  # A user whose default visitor already belongs to this property (e.g. an
  # admin picked an existing visitor when creating the user) is represented
  # there already; creating another visitor would duplicate them.
  def create_visitor_for_user
    return if user.default_visitor&.property_id == property_id

    visitor_name = user.name.presence || user.email.presence || "User ##{user.id}"
    visitor = property.visitors.create!(name: visitor_name, status: :active)
    user.update_column(:default_visitor_id, visitor.id) if user.default_visitor_id.nil?
  end
end
