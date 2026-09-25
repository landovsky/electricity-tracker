# frozen_string_literal: true

require "rails_helper"

# The 2025/26 settlement was done by hand on paper records; the resulting page lists family
# members and what each owes, so only people with access to the property may open it.
RSpec.describe SettlementsController, type: :request do
  let!(:sucha) { create(:property, subdomain: "sepot") }
  let(:path) { "/vyuctovani/sucha/2026" }

  context "a family member with access to Suchá opens the link from the family chat" do
    let(:member) { create(:user).tap { |u| u.properties << sucha } }

    before { sign_in_as(member) }

    it "shows the settlement page so each branch can see and split its share" do
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Vyúčtování elektřiny 2025/26")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  context "a user of another property (e.g. Tymlova) guesses the URL" do
    let(:outsider) { create(:user).tap { |u| u.properties << create(:property, subdomain: "tymlova") } }

    before { sign_in_as(outsider) }

    it "gets a 404 so the family's names and amounts don't leak" do
      get path
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Kristina")
    end
  end

  context "a year or property without a settlement" do
    it "is not found rather than rendering an empty page" do
      get "/vyuctovani/sucha/2025"
      expect(response).to have_http_status(:not_found)
    end
  end

  context "someone who is not logged in (link forwarded outside the family)" do
    before do
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_call_original
      allow_any_instance_of(ApplicationController).to receive(:logged_in?).and_call_original
    end

    it "is sent to the login page" do
      get path
      expect(response).to redirect_to(login_path)
    end
  end
end
