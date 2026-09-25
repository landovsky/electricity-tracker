# frozen_string_literal: true

# Join model linking users to properties they are allowed to access.
# TODO: Replace checkbox UI with a scalable search/select when user count grows.
class PropertyUser < ApplicationRecord
  belongs_to :property
  belongs_to :user

  validates :property_id, uniqueness: { scope: :user_id }

  after_create :create_visitor_for_user

  private

  def create_visitor_for_user
    # The user already has their own visitor on this property (seeded at bootstrap,
    # or kept from before their access was revoked and re-granted) — reuse it
    # rather than adding a second visitor with the same name.
    return if user.default_visitor&.property_id == property_id && user.default_visitor.kept?

    visitor_name = user.name.presence || user.email.presence || "User ##{user.id}"
    visitor = property.visitors.create!(name: visitor_name, status: :active)
    user.update_column(:default_visitor_id, visitor.id) if user.default_visitor_id.nil?
  end
end
