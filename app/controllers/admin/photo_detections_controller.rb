# frozen_string_literal: true

module Admin
  class PhotoDetectionsController < ApplicationController
    before_action :require_admin

    # GET /admin/detekce
    def index
      @detections = MeterPhotoDetection
        .where(property_id: current_property.id)
        .includes(:meter)
        .order(created_at: :desc)
        .limit(100)
    end

    private

    def require_admin
      redirect_to root_path, alert: t("auth.not_authorized") unless current_user&.admin?
    end
  end
end
