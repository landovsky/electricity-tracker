# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Available properties filtering", type: :request do
  let!(:property_sucha) { create(:property, name: "Sucha", subdomain: "sucha") }
  let!(:property_other) { create(:property, name: "Other Place", subdomain: "other") }
  let!(:property_no_sub) { create(:property, name: "No Subdomain", subdomain: nil) }

  # Every property needs at least one meter for the dashboard to render
  before do
    create(:meter, property: property_sucha, meter_type: "main", label: "Main")
    create(:meter, property: property_other, meter_type: "main", label: "Main")
    create(:meter, property: property_no_sub, meter_type: "main", label: "Main")
  end

  # Helper: attempt to switch to a property and check if session accepted it
  def switch_to(property)
    patch switch_property_path, params: { property_id: property.id }
  end

  def current_property_id
    session[:property_id]
  end

  describe "member user" do
    let(:member) { create(:user, :member) }

    before do
      create(:property_user, user: member, property: property_sucha)
      create(:property_user, user: member, property: property_other)
      create(:property_user, user: member, property: property_no_sub)
      sign_in_as(member)
    end

    context "on a subdomain" do
      before { host! "sucha.example.com" }

      it "can switch to subdomain-matching property" do
        switch_to(property_sucha)
        expect(current_property_id).to eq(property_sucha.id)
      end

      it "cannot switch to property from different subdomain" do
        switch_to(property_other)
        expect(current_property_id).not_to eq(property_other.id)
      end

      it "cannot switch to property without subdomain" do
        switch_to(property_no_sub)
        expect(current_property_id).not_to eq(property_no_sub.id)
      end
    end

    context "on bare domain" do
      before { host! "example.com" }

      it "can switch to any assigned property" do
        switch_to(property_sucha)
        expect(current_property_id).to eq(property_sucha.id)

        switch_to(property_other)
        expect(current_property_id).to eq(property_other.id)

        switch_to(property_no_sub)
        expect(current_property_id).to eq(property_no_sub.id)
      end

      it "cannot switch to unassigned property" do
        unassigned = create(:property, name: "Secret", subdomain: nil)
        switch_to(unassigned)
        expect(current_property_id).not_to eq(unassigned.id)
      end
    end
  end

  describe "admin user" do
    let(:admin) { create(:user, :admin) }

    before { sign_in_as(admin) }

    context "on a subdomain" do
      before { host! "sucha.example.com" }

      it "can switch to any property regardless of subdomain" do
        switch_to(property_sucha)
        expect(current_property_id).to eq(property_sucha.id)

        switch_to(property_other)
        expect(current_property_id).to eq(property_other.id)

        switch_to(property_no_sub)
        expect(current_property_id).to eq(property_no_sub.id)
      end
    end

    context "on bare domain" do
      before { host! "example.com" }

      it "can switch to any property" do
        switch_to(property_sucha)
        expect(current_property_id).to eq(property_sucha.id)

        switch_to(property_other)
        expect(current_property_id).to eq(property_other.id)
      end
    end

    it "does not need explicit property_user assignment" do
      expect(admin.property_users).to be_empty

      host! "example.com"
      switch_to(property_sucha)
      expect(current_property_id).to eq(property_sucha.id)
    end
  end
end
