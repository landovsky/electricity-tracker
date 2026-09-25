# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsersController, type: :request do
  let!(:property) { create(:property) }

  before { create(:meter, property: property, meter_type: "main", label: "Main") }

  def log_in_for_real(user)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_call_original
    allow_any_instance_of(ApplicationController).to receive(:logged_in?).and_call_original

    token = GenerateMagicLinkToken.run!(user: user)
    get auth_verify_path(token: token)
    post auth_verify_path(token: token)
  end

  describe "POST /users" do
    context "an admin adds a family member (logins no longer grant property access on their own)" do
      it "gives the member access to the admin's property, so their first login lands on a working dashboard" do
        post users_path, params: { user: { name: "Petr", email: "petr@example.com", role: "member" } }
        member = User.find_by!(email: "petr@example.com")

        expect(member.properties).to eq([ property ])

        log_in_for_real(member)
        expect(response).to redirect_to(root_path)

        get root_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(I18n.t("dashboard.no_property"))
        expect(session[:property_id]).to eq(property.id)
      end
    end

    context "the admin links the new member to an existing visitor (e.g. one imported from the old spreadsheet)" do
      let!(:visitor) { create(:visitor, property: property, name: "Petr") }

      it "grants that visitor's property without creating a duplicate visitor for the member" do
        expect {
          post users_path, params: {
            user: { name: "Petr", email: "petr@example.com", role: "member", default_visitor_id: visitor.id }
          }
        }.not_to change(Visitor, :count)

        member = User.find_by!(email: "petr@example.com")
        expect(member.properties).to eq([ property ])
        expect(member.default_visitor).to eq(visitor)
      end
    end

    context "the form is invalid" do
      it "grants nothing and re-renders the form" do
        expect {
          post users_path, params: { user: { name: "", email: "", role: "member" } }
        }.not_to change(PropertyUser, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
