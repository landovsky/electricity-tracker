# frozen_string_literal: true

# Assigns a default property to a newly registered user.
#
# Current strategy: assign the oldest property (by created_at).
# This is the single place to change if the assignment strategy evolves
# (e.g. invite-based, domain-based, or manual approval).
class AssignDefaultProperty < ApplicationService
  object :user

  def execute
    property = Property.kept.order(:created_at).first
    return unless property

    user.properties << property unless user.properties.exists?(property.id)
  end
end
