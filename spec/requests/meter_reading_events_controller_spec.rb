# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Deleting meter reading events and what the dashboard shows afterwards", type: :request do
  let(:property) { create(:property) }
  let!(:main_meter) { create(:meter, property: property, meter_type: "main", label: "Main meter") }
  let!(:secondary_meter) { create(:meter, property: property, meter_type: "secondary", label: "Upper floor meter") }
  let(:visitor) { create(:visitor, name: "Alice", property: property) }

  before { property }

  def checkin_list
    response.body[/Available visitors for check-in: [^<]*/]
  end

  context "a visitor was checked in by mistake and the check-in is deleted from history" do
    let!(:stay) { create(:stay, :open, visitor: visitor, property: property, check_in_at: 1.day.ago) }

    it "no longer shows the visitor as present, and offers them for check-in again" do
      delete meter_reading_event_path(stay.check_in_event)
      get root_path

      expect(checkin_list).to include("Alice")
      expect(response.body).not_to include(%(data-stay-id="#{stay.id}"))
      expect(response.body).to include(I18n.t("dashboard.house_status.nobody_here"))
    end
  end

  context "a check-out is deleted after the visitor already checked in again" do
    let!(:first_stay) do
      create(:stay, :closed, visitor: visitor, property: property,
             check_in_at: 10.days.ago, check_out_at: 8.days.ago,
             main_reading_in: 1000.0, main_reading_out: 1050.0)
    end
    let!(:second_stay) do
      create(:stay, :open, visitor: visitor, property: property, check_in_at: 2.days.ago,
             main_reading_in: 1100.0, secondary_reading_in: 600.0)
    end

    it "refuses with an explanation, so the visitor never has two open stays" do
      delete meter_reading_event_path(first_stay.check_out_event)

      expect(flash[:alert]).to eq(I18n.t("meter_reading_events.destroy.has_later_stay"))
      expect(first_stay.reload).to be_closed
      expect(first_stay.check_out_event).not_to be_discarded
    end
  end

  # Production holds rows written by the pre-f654054 delete code, which discarded
  # the event but left the stay pointing at it.
  context "legacy stay that is open but whose check-in event was discarded" do
    let!(:orphan_stay) do
      create(:stay, :open, visitor: visitor, property: property, check_in_at: 3.days.ago)
        .tap { |s| s.check_in_event.discard! }
    end

    it "does not show the visitor as present and lets them check in" do
      get root_path

      expect(checkin_list).to include("Alice")
      expect(response.body).not_to include(%(data-stay-id="#{orphan_stay.id}"))
    end

    it "does not block a new check-in with the one-open-stay rule (C2)" do
      expect {
        post stays_path, params: { visitor_id: visitor.id, property_id: property.id,
                                   recorded_at: Time.current.iso8601,
                                   main_meter_reading: 1200.0, secondary_meter_reading: 600.0 }
      }.to change { visitor.stays.live.open.count }.from(0).to(1)
    end

    it "cannot be checked out by stay id, since it is not a real presence" do
      patch check_out_stay_path(orphan_stay), params: { main_meter_reading: 1200.0 }

      expect(orphan_stay.reload).to be_open
    end
  end

  context "legacy stay that is closed but whose check-out event was discarded" do
    let!(:stay) do
      create(:stay, :closed, visitor: visitor, property: property,
             check_in_at: 3.days.ago, check_out_at: 2.days.ago)
        .tap { |s| s.check_out_event.discard! }
    end

    it "stays closed: the visitor is not shown as present and can check in" do
      get root_path

      expect(checkin_list).to include("Alice")
      expect(response.body).not_to include(%(data-stay-id="#{stay.id}"))
    end
  end
end

# Spec section 9: "Edit / delete any record" is admin-only. Deleting an event
# discards or reopens stays, i.e. it rewrites everyone's consumption history.
RSpec.describe MeterReadingEventsController, type: :request do
  let(:property) { create(:property) }
  let!(:stay) do
    create(:stay, :closed, visitor: create(:visitor, name: "Jana", property: property), property: property,
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

        expect(response.body).to include("Jana")
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
