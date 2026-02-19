# frozen_string_literal: true

module Admin
  class MigrationsController < ApplicationController
    before_action :require_admin

    # POST /admin/migrations/xls
    def xls
      XlsDataMigration.run
      redirect_back fallback_location: root_path, notice: t("admin.migrations.xls_success")
    end

    private

    def require_admin
      redirect_to root_path, alert: t("auth.not_authorized") unless current_user&.admin?
    end
  end
end
