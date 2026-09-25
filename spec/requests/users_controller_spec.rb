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

  describe "PATCH /uzivatele/:id (update)" do
    context "the user registered via SMS and has no email" do
      let!(:sms_user) { create(:user, :phone_only, name: "Babička") }

      it "saves role changes with the email field left empty, storing no email" do
        patch user_path(sms_user), params: { user: { name: "Babička", email: "", phone_number: sms_user.phone_number, role: "admin" } }

        expect(response).to redirect_to(user_path(sms_user))
        sms_user.reload
        expect(sms_user.role).to eq("admin")
        expect(sms_user.email).to be_nil
      end

      it "lets a second SMS-only user be saved too, because blank emails never collide on uniqueness" do
        other = create(:user, :phone_only, name: "Děda")
        patch user_path(sms_user), params: { user: { name: "Babička", email: "", phone_number: sms_user.phone_number } }

        patch user_path(other), params: { user: { name: "Děda", email: "", phone_number: other.phone_number } }

        expect(response).to redirect_to(user_path(other))
        expect(other.reload.email).to be_nil
      end
    end

    context "an email-only user is saved with the phone field left empty" do
      let!(:first) { create(:user, name: "Anna") }
      let!(:second) { create(:user, name: "Bohouš") }

      it "stores no phone number, so a second such user does not collide on phone uniqueness" do
        patch user_path(first), params: { user: { name: "Anna", email: first.email, phone_number: "" } }
        patch user_path(second), params: { user: { name: "Bohouš", email: second.email, phone_number: "" } }

        expect(response).to redirect_to(user_path(second))
        expect(second.reload.phone_number).to be_nil
      end
    end
  end

  describe "GET /uzivatele/:id/edit" do
    context "an SMS-only user has no email to fill in" do
      let!(:sms_user) { create(:user, :phone_only) }

      it "does not mark the email field as required, so the browser lets the form submit" do
        get edit_user_path(sms_user)

        email_input = Nokogiri::HTML(response.body).at_css("input#user_email")
        expect(email_input["required"]).to be_nil
        expect(email_input["type"]).to eq("email")
      end
    end

    context "the user's default visitor is archived, so it is not among the active visitors" do
      let(:archived_visitor) { create(:visitor, :archived, name: "Starý Profil", property: property) }
      let!(:user) { create(:user, default_visitor_id: archived_visitor.id) }

      it "still offers it pre-selected, so saving other fields does not silently clear it" do
        get edit_user_path(user)

        selected = Nokogiri::HTML(response.body).at_css("select#user_default_visitor_id option[selected]")
        expect(selected&.[]("value")).to eq(archived_visitor.id.to_s)
      end
    end

    context "the user's default visitor belongs to a property other than the admin's current one" do
      let(:other_property) { create(:property, name: "Tymlova") }
      let(:foreign_visitor) { create(:visitor, name: "Tymlova Profil", property: other_property) }
      let!(:user) { create(:user, default_visitor_id: foreign_visitor.id) }

      it "still offers it pre-selected, so editing a phone number does not wipe it" do
        get edit_user_path(user)

        selected = Nokogiri::HTML(response.body).at_css("select#user_default_visitor_id option[selected]")
        expect(selected&.[]("value")).to eq(foreign_visitor.id.to_s)
      end
    end
  end
end
