# frozen_string_literal: true

# Handles switching the active property for the current user session.
# The selected property_id is stored in the session and used across all pages.
class PropertySwitchController < ApplicationController
  # PATCH /switch_property
  def update
    property = available_properties.find_by(id: params[:property_id])

    if property
      session[:property_id] = property.id
    end

    redirect_back fallback_location: root_path
  end
end
