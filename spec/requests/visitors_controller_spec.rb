# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VisitorsController, type: :request do
  let(:member_user) { create(:user, role: :member) }
  let(:admin_user) { create(:user, role: :admin) }
  let(:visitor) { create(:visitor, name: "Alice", status: :active) }
  let(:archived_visitor) { create(:visitor, :discarded, name: "Bob") }

  # Stub authentication for all tests
  before do
    # The controller's require_authentication method creates a user automatically
    # but we'll ensure one exists for consistency
    member_user
    admin_user
  end

  describe "GET /visitors (index)" do
    before do
      visitor
      archived_visitor
    end

    context "without include_archived param" do
      it "returns success" do
        get visitors_path
        expect(response).to have_http_status(:success)
      end

      it "lists only kept visitors" do
        get visitors_path
        expect(response.body).to include("Alice")
        expect(response.body).not_to include("Bob")
      end
    end

    context "with include_archived=true" do
      it "lists all visitors including archived" do
        get visitors_path, params: { include_archived: "true" }
        expect(response.body).to include("Alice")
        expect(response.body).to include("Bob")
      end
    end
  end

  describe "GET /visitors/:id (show)" do
    let(:property) { create(:property) }
    let!(:stay) { create(:stay, :closed, visitor: visitor, property: property) }
    let!(:manual_entry) { create(:manual_consumption_entry, visitor: visitor, property: property, kwh: 50.0, date: Date.today) }

    it "returns success" do
      get visitor_path(visitor)
      expect(response).to have_http_status(:success)
    end

    it "displays visitor details" do
      get visitor_path(visitor)
      expect(response.body).to include("Alice")
    end

    context "when visitor does not exist" do
      it "redirects to visitors index with alert" do
        get visitor_path(id: 99999)
        expect(response).to redirect_to(visitors_path)
        expect(flash[:alert]).to include("Visitor not found")
      end
    end
  end

  describe "GET /visitors/new (new)" do
    it "returns success" do
      get new_visitor_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /visitors (create)" do
    let(:valid_params) do
      {
        visitor: {
          name: "Charlie",
          status: "active",
          note: "Friend of the family"
        }
      }
    end

    context "with valid parameters" do
      it "creates a new visitor" do
        expect {
          post visitors_path, params: valid_params
        }.to change(Visitor, :count).by(1)
      end

      it "redirects to visitors index with success notice" do
        post visitors_path, params: valid_params
        expect(response).to redirect_to(visitors_path)
        expect(flash[:notice]).to include("Visitor Charlie created successfully")
      end

      it "sets visitor attributes correctly" do
        post visitors_path, params: valid_params
        visitor = Visitor.last
        expect(visitor.name).to eq("Charlie")
        expect(visitor.status).to eq("active")
        expect(visitor.note).to eq("Friend of the family")
      end
    end

    context "with invalid parameters" do
      let(:invalid_params) do
        {
          visitor: {
            name: "", # Name is required
            status: "active"
          }
        }
      end

      it "does not create a visitor" do
        expect {
          post visitors_path, params: invalid_params
        }.not_to change(Visitor, :count)
      end

      it "returns unprocessable_entity status" do
        post visitors_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /visitors/:id/edit (edit)" do
    context "as admin user" do
      before do
        # Stub current_user to return admin
        allow_any_instance_of(VisitorsController).to receive(:current_user).and_return(admin_user)
      end

      it "returns success" do
        get edit_visitor_path(visitor)
        expect(response).to have_http_status(:success)
      end
    end

    context "as member user" do
      before do
        allow_any_instance_of(VisitorsController).to receive(:current_user).and_return(member_user)
      end

      it "redirects to visitors index with alert" do
        get edit_visitor_path(visitor)
        expect(response).to redirect_to(visitors_path)
        expect(flash[:alert]).to include("Only admins can perform this action")
      end
    end
  end

  describe "PATCH /visitors/:id (update)" do
    let(:update_params) do
      {
        visitor: {
          name: "Alice Updated",
          note: "Updated note"
        }
      }
    end

    context "as admin user" do
      before do
        allow_any_instance_of(VisitorsController).to receive(:current_user).and_return(admin_user)
      end

      context "with valid parameters" do
        it "updates the visitor" do
          patch visitor_path(visitor), params: update_params
          visitor.reload
          expect(visitor.name).to eq("Alice Updated")
          expect(visitor.note).to eq("Updated note")
        end

        it "redirects to visitor show with success notice" do
          patch visitor_path(visitor), params: update_params
          expect(response).to redirect_to(visitor_path(visitor))
          expect(flash[:notice]).to include("Visitor Alice Updated updated successfully")
        end
      end

      context "with invalid parameters" do
        let(:invalid_params) do
          {
            visitor: {
              name: "" # Name cannot be blank
            }
          }
        end

        it "does not update the visitor" do
          original_name = visitor.name
          patch visitor_path(visitor), params: invalid_params
          visitor.reload
          expect(visitor.name).to eq(original_name)
        end

        it "returns unprocessable_entity status" do
          patch visitor_path(visitor), params: invalid_params
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context "as member user" do
      before do
        allow_any_instance_of(VisitorsController).to receive(:current_user).and_return(member_user)
      end

      it "redirects to visitors index with alert" do
        patch visitor_path(visitor), params: update_params
        expect(response).to redirect_to(visitors_path)
        expect(flash[:alert]).to include("Only admins can perform this action")
      end

      it "does not update the visitor" do
        original_name = visitor.name
        patch visitor_path(visitor), params: update_params
        visitor.reload
        expect(visitor.name).to eq(original_name)
      end
    end
  end

  describe "PATCH /visitors/:id/archive (archive)" do
    context "as admin user" do
      before do
        allow_any_instance_of(VisitorsController).to receive(:current_user).and_return(admin_user)
      end

      it "soft deletes the visitor" do
        patch archive_visitor_path(visitor)
        visitor.reload
        expect(visitor.discarded?).to be true
      end

      it "redirects to visitors index with success notice" do
        patch archive_visitor_path(visitor)
        expect(response).to redirect_to(visitors_path)
        expect(flash[:notice]).to include("Visitor Alice archived successfully")
      end

      it "removes visitor from default scope" do
        patch archive_visitor_path(visitor)
        expect(Visitor.kept.find_by(id: visitor.id)).to be_nil
        expect(Visitor.with_discarded.find_by(id: visitor.id)).to be_present
      end
    end

    context "as member user" do
      before do
        allow_any_instance_of(VisitorsController).to receive(:current_user).and_return(member_user)
      end

      it "redirects to visitors index with alert" do
        patch archive_visitor_path(visitor)
        expect(response).to redirect_to(visitors_path)
        expect(flash[:alert]).to include("Only admins can perform this action")
      end

      it "does not archive the visitor" do
        patch archive_visitor_path(visitor)
        visitor.reload
        expect(visitor.discarded?).to be false
      end
    end
  end

  context "when not authenticated" do
    before do
      # Undo the auto-sign-in from authentication_helpers.rb
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_call_original
      allow_any_instance_of(ApplicationController).to receive(:logged_in?).and_call_original
    end

    it "redirects to login" do
      get visitors_path
      expect(response).to redirect_to(login_path)
    end
  end
end
