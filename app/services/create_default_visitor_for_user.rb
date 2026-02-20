# frozen_string_literal: true

# Service to create a default Visitor for a newly onboarded User.
#
# Creates a Visitor record from the user's name, sets it as the user's
# default_visitor, and returns the created Visitor.
#
# Idempotent: if the user already has a default_visitor, returns it without
# creating a second one.
#
# Both the Visitor creation and the user update happen inside a transaction
# so that a failure in either leaves the database unchanged.
class CreateDefaultVisitorForUser < ApplicationService
  record :user, class_name: "User"
  record :property, class_name: "Property", default: nil

  def execute
    return user.default_visitor if user.default_visitor.present?

    resolved_property = property || user.properties.first
    return nil unless resolved_property

    ActiveRecord::Base.transaction do
      visitor = resolved_property.visitors.create!(name: user.name, status: :active)
      user.update_column(:default_visitor_id, visitor.id)
      visitor
    end
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.join(", "))
    nil
  end
end
