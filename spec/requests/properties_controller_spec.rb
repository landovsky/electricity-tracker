# frozen_string_literal: true

require "rails_helper"

RSpec.describe PropertiesController, type: :request do
  let(:property) { create(:property, name: "Suchá") }
  let(:member_a) { create(:user, :member) }
  let(:member_b) { create(:user, :member) }

  before do
    create(:property_user, property: property, user: member_a)
    create(:property_user, property: property, user: member_b)
  end

  describe "PATCH /nemovitosti/:id (update)" do
    context "an admin fixes the address in the edit form, which has no member checkboxes" do
      it "keeps every family member's access, so nobody is locked out of the dashboard" do
        patch property_path(property), params: { property: { name: "Suchá", address: "Nová adresa 1" } }

        expect(response).to redirect_to(property_path(property))
        expect(property.reload.address).to eq("Nová adresa 1")
        expect(property.user_ids).to contain_exactly(member_a.id, member_b.id)
      end
    end

    context "the form does send the member checkboxes" do
      it "syncs membership to the ticked users" do
        patch property_path(property), params: { property: { name: "Suchá", user_ids: [ "", member_a.id.to_s ] } }

        expect(property.reload.user_ids).to contain_exactly(member_a.id)
      end

      it "still lets an admin deliberately untick everyone (only the hidden blank entry arrives)" do
        patch property_path(property), params: { property: { name: "Suchá", user_ids: [ "" ] } }

        expect(property.reload.user_ids).to be_empty
      end
    end
  end

  describe "GET /nemovitosti/:id (show)" do
    context "the meter list shows the last reading in the Czech UI" do
      let(:meter) { create(:meter, property: property) }

      before do
        event = create(:meter_reading_event, event_type: :periodic)
        create(:meter_reading, meter_reading_event: event, meter: meter, value_kwh: 12_487.5)
      end

      it "formats it with Czech separators like the dashboard does" do
        I18n.with_locale(:cs) { get property_path(property) }

        expect(response.body).to include("12 487,5 kWh")
      end
    end
  end

  describe "POST /nemovitosti (create)" do
    context "the new-property form has no member checkboxes" do
      it "creates the property without touching any membership" do
        expect {
          post properties_path, params: { property: { name: "Tymlova" } }
        }.to change(Property, :count).by(1)

        expect(Property.find_by!(name: "Tymlova").user_ids).to be_empty
        expect(property.reload.user_ids).to contain_exactly(member_a.id, member_b.id)
      end
    end
  end
end
