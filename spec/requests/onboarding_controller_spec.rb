# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingController, type: :request do
  let(:property) { create(:property) }
  let(:user) { create(:user, :not_onboarded) }

  before do
    property # ensure property exists
    # Link user to property without triggering visitor-creation callback (user has no name yet)
    PropertyUser.insert!({ user_id: user.id, property_id: property.id, created_at: Time.current, updated_at: Time.current })
    sign_in_as(user)
  end

  describe "PATCH /onboarding" do
    context "with a valid name" do
      it "creates a Visitor with the user's name" do
        expect {
          patch onboarding_path, params: { name: "Marketa Novakova" }
        }.to change(Visitor, :count).by(1)

        visitor = Visitor.last
        expect(visitor.name).to eq("Marketa Novakova")
        expect(visitor.status).to eq("active")
      end

      it "sets default_visitor_id on the user" do
        patch onboarding_path, params: { name: "Marketa Novakova" }

        user.reload
        expect(user.default_visitor_id).to be_present
        expect(user.default_visitor.name).to eq("Marketa Novakova")
      end

      it "redirects to root with success notice" do
        patch onboarding_path, params: { name: "Marketa Novakova" }

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to be_present
      end
    end

    context "with a blank name" do
      it "does not create a Visitor" do
        expect {
          patch onboarding_path, params: { name: "" }
        }.not_to change(Visitor, :count)
      end

      it "renders the form with an error" do
        patch onboarding_path, params: { name: "" }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not set default_visitor_id on the user" do
        patch onboarding_path, params: { name: "" }

        user.reload
        expect(user.default_visitor_id).to be_nil
      end
    end

    context "a self-registered user has no property yet (access is granted only after a verified login)" do
      let(:newcomer) { create(:user, :not_onboarded) }

      before { sign_in_as(newcomer) }

      it "assigns the default property and creates exactly one visitor with the entered name" do
        expect {
          patch onboarding_path, params: { name: "Jan Novak" }
        }.to change(Visitor, :count).by(1)

        newcomer.reload
        expect(newcomer.properties).to include(property)
        expect(newcomer.default_visitor.name).to eq("Jan Novak")
      end
    end

    context "a user registered under the old flow already has a visitor auto-named after their email" do
      let(:legacy_user) { create(:user, :not_onboarded, email: "jana@example.com") }

      before do
        legacy_user.properties << property # callback names the visitor after the email
        sign_in_as(legacy_user.reload)
      end

      it "renames that visitor to the entered name instead of keeping the email for everyone to see" do
        expect {
          patch onboarding_path, params: { name: "Jana" }
        }.not_to change(Visitor, :count)

        expect(legacy_user.reload.default_visitor.name).to eq("Jana")
      end
    end

    context "when user already has a default_visitor (re-submit guard)" do
      let(:existing_visitor) { create(:visitor, name: "Jiri Dvorak") }

      before do
        # Simulate user who already went through onboarding once
        user.update!(name: "Jiri Dvorak")
        user.update_column(:default_visitor_id, existing_visitor.id)
      end

      it "does not create a second Visitor" do
        expect {
          patch onboarding_path, params: { name: "Jiri Dvorak" }
        }.not_to change(Visitor, :count)
      end

      it "redirects to root" do
        patch onboarding_path, params: { name: "Jiri Dvorak" }

        expect(response).to redirect_to(root_path)
      end
    end
  end
end
