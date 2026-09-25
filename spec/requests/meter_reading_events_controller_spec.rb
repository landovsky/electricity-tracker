# frozen_string_literal: true

require "rails_helper"

# Spec section 9: "Edit / delete any record" is admin-only. Deleting an event
# discards or reopens stays, i.e. it rewrites everyone's consumption history.
RSpec.describe MeterReadingEventsController, type: :request do
  let(:property) { create(:property) }
  let!(:stay) do
    create(:stay, :closed, visitor: create(:visitor, property: property), property: property,
                           check_in_at: 3.days.ago, check_out_at: 1.day.ago)
  end
  let(:check_out_event) { stay.check_out_event }

  describe "DELETE /odecty/:id" do
    context "a family member (not admin) tries to delete a check-out" do
      let(:member) { create(:user, :member) }

      before do
        create(:property_user, user: member, property: property)
        sign_in_as(member)
      end

      it "refuses, so the stay is not silently reopened by a non-admin" do
        delete meter_reading_event_path(check_out_event)

        expect(response).to redirect_to(readings_history_path)
        expect(flash[:alert]).to eq(I18n.t("meter_reading_events.admin_required"))
        expect(check_out_event.reload).not_to be_discarded
        expect(stay.reload).to be_closed
      end

      it "hides the delete button in the history, so members are not offered an action they cannot take" do
        get readings_history_path

        expect(response.body).to include(stay.visitor.name)
        expect(response.body).not_to include(meter_reading_event_path(check_out_event))
      end
    end

    context "an admin deletes a check-out of the property they are working in" do
      it "deletes it and reopens the stay" do
        delete meter_reading_event_path(check_out_event)

        expect(check_out_event.reload).to be_discarded
        expect(stay.reload).to be_open
      end

      it "offers the delete button in the history" do
        get readings_history_path

        expect(response.body).to include(meter_reading_event_path(check_out_event))
      end
    end

    context "an admin sends the id of an event belonging to another property than the selected one" do
      let(:other_property) { create(:property, name: "AAA first by name") }

      before do
        create(:meter, :main, property: other_property)
        patch switch_property_path, params: { property_id: other_property.id }
      end

      it "refuses, so an event is only deleted from the property whose history is on screen" do
        delete meter_reading_event_path(check_out_event)

        expect(response).to redirect_to(readings_history_path)
        expect(flash[:alert]).to eq(I18n.t("meter_reading_events.destroy.not_found"))
        expect(check_out_event.reload).not_to be_discarded
      end
    end
  end
end
