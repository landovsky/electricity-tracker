# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::MigrationsController, type: :request do
  let(:property) { create(:property) }
  let(:visitor) { create(:visitor, property: property) }

  around do |example|
    original = ENV.fetch(XlsDataMigration::OPT_IN_ENV, nil)
    example.run
  ensure
    ENV[XlsDataMigration::OPT_IN_ENV] = original
  end

  describe "POST /admin/migrace/xls" do
    context "an admin clicks 'Import XLS' on production that already has stays and readings" do
      before do
        ENV.delete(XlsDataMigration::OPT_IN_ENV)
        create(:stay, visitor: visitor, property: property)
      end

      it "refuses with an explanation and keeps every stay, so live data is never wiped by one click" do
        expect(XlsDataMigration).not_to receive(:run)

        expect { post admin_xls_migration_path }.not_to change(Stay, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(
          I18n.t("admin.migrations.xls_refused", env: "ALLOW_DESTRUCTIVE_XLS_MIGRATION")
        )
      end
    end

    context "the operator explicitly set ALLOW_DESTRUCTIVE_XLS_MIGRATION=true on the deployment" do
      before do
        ENV[XlsDataMigration::OPT_IN_ENV] = "true"
        create(:stay, visitor: visitor, property: property)
      end

      it "runs the import, because the destructive action was consciously allowed" do
        expect(XlsDataMigration).to receive(:run)

        post admin_xls_migration_path

        expect(flash[:notice]).to eq(I18n.t("admin.migrations.xls_success"))
      end
    end
  end
end
