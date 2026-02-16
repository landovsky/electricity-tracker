# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ManualConsumptionEntries", type: :request do
  let(:visitor) { create(:visitor) }
  let(:property) { create(:property) }
  let(:user) { create(:user) }

  let(:valid_params) do
    {
      visitor_id: visitor.id,
      property_id: property.id,
      date: Date.current.to_s,
      kwh: 15.5,
      note: "EV charging"
    }
  end

  describe "POST /manual_consumption_entries" do
    context "with valid parameters" do
      it "creates a new manual consumption entry" do
        expect {
          post manual_consumption_entries_path, params: valid_params
        }.to change(ManualConsumptionEntry, :count).by(1)
      end

      it "sets all attributes correctly" do
        post manual_consumption_entries_path, params: valid_params

        entry = ManualConsumptionEntry.last
        expect(entry.visitor).to eq(visitor)
        expect(entry.property).to eq(property)
        expect(entry.date).to eq(Date.current)
        expect(entry.kwh).to eq(15.5)
        expect(entry.note).to eq("EV charging")
        expect(entry.recorded_by_user).to be_present
      end

      it "redirects to root with success flash" do
        post manual_consumption_entries_path, params: valid_params

        expect(response).to redirect_to(root_path)
        expect(flash[:success]).to match(/Manual consumption entry recorded/)
        expect(flash[:success]).to match(/15.5 kWh/)
        expect(flash[:success]).to match(/#{visitor.name}/)
      end

      it "records the entry in audit log" do
        post manual_consumption_entries_path, params: valid_params

        entry = ManualConsumptionEntry.last
        expect(entry.audits.count).to eq(1)
        expect(entry.audits.first.action).to eq("create")
      end
    end

    context "with default property (property_id not provided)" do
      it "defaults to Property.first" do
        params = valid_params.except(:property_id)

        post manual_consumption_entries_path, params: params

        entry = ManualConsumptionEntry.last
        expect(entry.property).to eq(Property.first)
      end
    end

    context "with default date (date not provided)" do
      it "defaults to Date.current" do
        params = valid_params.except(:date)

        post manual_consumption_entries_path, params: params

        entry = ManualConsumptionEntry.last
        expect(entry.date).to eq(Date.current)
      end
    end

    context "with missing required parameters" do
      it "fails when visitor_id is missing" do
        params = valid_params.except(:visitor_id)

        expect {
          post manual_consumption_entries_path, params: params
        }.not_to change(ManualConsumptionEntry, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to be_present
      end

      it "fails when visitor_id is invalid" do
        params = valid_params.merge(visitor_id: 99999)

        expect {
          post manual_consumption_entries_path, params: params
        }.not_to change(ManualConsumptionEntry, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to be_present
      end

      it "fails when kwh is missing" do
        params = valid_params.except(:kwh)

        expect {
          post manual_consumption_entries_path, params: params
        }.not_to change(ManualConsumptionEntry, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to be_present
      end

      it "fails when note is missing" do
        params = valid_params.except(:note)

        expect {
          post manual_consumption_entries_path, params: params
        }.not_to change(ManualConsumptionEntry, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to be_present
      end

      it "fails when note is blank" do
        params = valid_params.merge(note: "")

        expect {
          post manual_consumption_entries_path, params: params
        }.not_to change(ManualConsumptionEntry, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to be_present
      end
    end

    context "constraint C7: positive kWh validation" do
      it "fails when kwh is zero" do
        params = valid_params.merge(kwh: 0)

        expect {
          post manual_consumption_entries_path, params: params
        }.not_to change(ManualConsumptionEntry, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to match(/must be positive/)
      end

      it "fails when kwh is negative" do
        params = valid_params.merge(kwh: -5.5)

        expect {
          post manual_consumption_entries_path, params: params
        }.not_to change(ManualConsumptionEntry, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to match(/must be positive/)
      end

      it "allows very small positive values" do
        params = valid_params.merge(kwh: 0.01)

        expect {
          post manual_consumption_entries_path, params: params
        }.to change(ManualConsumptionEntry, :count).by(1)

        entry = ManualConsumptionEntry.last
        expect(entry.kwh).to eq(0.01)
      end

      it "allows large positive values" do
        params = valid_params.merge(kwh: 1000.5)

        expect {
          post manual_consumption_entries_path, params: params
        }.to change(ManualConsumptionEntry, :count).by(1)

        entry = ManualConsumptionEntry.last
        expect(entry.kwh).to eq(1000.5)
      end
    end

    context "constraint C8: period consumption warning (soft validation)" do
      # C8 is a soft validation that adds a warning, not a blocking error
      # The entry should still be created, but a warning flash should be displayed
      #
      # NOTE: The actual C8 validation logic is not implemented yet
      # (it requires period analysis service). This test verifies that:
      # 1. The entry is created despite the warning
      # 2. The controller properly displays warnings from outcome.errors[:consumption_warning]
      #
      # TODO: Once period analysis service is implemented, create a test scenario
      # that actually triggers the C8 warning by:
      # 1. Setting up a period with known consumption (e.g., 100 kWh)
      # 2. Creating manual entries/stays that consume most of it
      # 3. Attempting to create a manual entry that exceeds remaining consumption
      # 4. Verifying the warning is displayed

      it "creates entry successfully (C8 not yet implemented)" do
        # This is a placeholder test
        # Currently C8 validation is stubbed in the service
        params = valid_params.merge(kwh: 1000) # Unrealistically high value

        expect {
          post manual_consumption_entries_path, params: params
        }.to change(ManualConsumptionEntry, :count).by(1)

        # Entry should be created despite potentially exceeding period consumption
        entry = ManualConsumptionEntry.last
        expect(entry.kwh).to eq(1000)
      end

      # TODO: Add this test once C8 is implemented in the service
      # it "displays warning flash when exceeding period consumption" do
      #   # Set up a period with limited consumption
      #   # ...
      #
      #   params = valid_params.merge(kwh: 1000)
      #   post manual_consumption_entries_path, params: params
      #
      #   expect(response).to redirect_to(root_path)
      #   expect(flash[:warning]).to match(/exceeds unattributed consumption/)
      # end
    end

    context "with invalid property_id" do
      it "fails when property does not exist" do
        params = valid_params.merge(property_id: 99999)

        expect {
          post manual_consumption_entries_path, params: params
        }.not_to change(ManualConsumptionEntry, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to be_present
      end
    end

    context "with invalid date format" do
      it "fails when date cannot be parsed" do
        params = valid_params.merge(date: "not-a-date")

        expect {
          post manual_consumption_entries_path, params: params
        }.not_to change(ManualConsumptionEntry, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to be_present
      end
    end

    context "with various date formats" do
      it "accepts ISO 8601 date format" do
        params = valid_params.merge(date: "2024-01-15")

        post manual_consumption_entries_path, params: params

        entry = ManualConsumptionEntry.last
        expect(entry.date).to eq(Date.new(2024, 1, 15))
      end

      it "accepts date with dashes" do
        params = valid_params.merge(date: "2024-03-22")

        post manual_consumption_entries_path, params: params

        entry = ManualConsumptionEntry.last
        expect(entry.date).to eq(Date.new(2024, 3, 22))
      end
    end

    context "authentication" do
      # NOTE: Authentication is currently stubbed
      # The require_authentication method exists but does nothing
      # current_user returns User.first or creates a system user
      #
      # TODO: Once real authentication is implemented, add tests for:
      # - Unauthenticated users are redirected to login
      # - Authenticated users can create entries
      # - Entry is recorded with the correct user

      it "allows request (authentication stubbed)" do
        post manual_consumption_entries_path, params: valid_params

        expect(response).to redirect_to(root_path)
        expect(flash[:success]).to be_present
      end

      it "records the entry with current_user" do
        post manual_consumption_entries_path, params: valid_params

        entry = ManualConsumptionEntry.last
        expect(entry.recorded_by_user).to be_present
        expect(entry.recorded_by_user).to be_a(User)
      end
    end

    context "edge cases" do
      it "handles visitor with special characters in name" do
        visitor_with_special_chars = create(:visitor, name: "O'Brien & Sons")
        params = valid_params.merge(visitor_id: visitor_with_special_chars.id)

        expect {
          post manual_consumption_entries_path, params: params
        }.to change(ManualConsumptionEntry, :count).by(1)

        entry = ManualConsumptionEntry.last
        expect(entry.visitor.name).to eq("O'Brien & Sons")
      end

      it "handles very long notes" do
        long_note = "A" * 1000
        params = valid_params.merge(note: long_note)

        expect {
          post manual_consumption_entries_path, params: params
        }.to change(ManualConsumptionEntry, :count).by(1)

        entry = ManualConsumptionEntry.last
        expect(entry.note).to eq(long_note)
      end

      it "handles decimal kWh values" do
        params = valid_params.merge(kwh: 12.34)

        expect {
          post manual_consumption_entries_path, params: params
        }.to change(ManualConsumptionEntry, :count).by(1)

        entry = ManualConsumptionEntry.last
        expect(entry.kwh.to_f).to eq(12.34)
      end

      it "handles archived visitor" do
        archived_visitor = create(:visitor, :archived)
        params = valid_params.merge(visitor_id: archived_visitor.id)

        expect {
          post manual_consumption_entries_path, params: params
        }.to change(ManualConsumptionEntry, :count).by(1)

        entry = ManualConsumptionEntry.last
        expect(entry.visitor).to eq(archived_visitor)
        expect(entry.visitor.status).to eq("archived")
      end
    end

    context "multiple entries" do
      it "allows multiple entries for the same visitor on the same day" do
        post manual_consumption_entries_path, params: valid_params

        expect {
          post manual_consumption_entries_path, params: valid_params.merge(
            kwh: 20.0,
            note: "Second charging session"
          )
        }.to change(ManualConsumptionEntry, :count).by(1)

        entries = ManualConsumptionEntry.where(visitor: visitor, date: Date.current)
        expect(entries.count).to eq(2)
      end

      it "allows entries for different visitors on the same day" do
        other_visitor = create(:visitor)

        post manual_consumption_entries_path, params: valid_params

        expect {
          post manual_consumption_entries_path, params: valid_params.merge(
            visitor_id: other_visitor.id,
            note: "Different visitor"
          )
        }.to change(ManualConsumptionEntry, :count).by(1)

        expect(ManualConsumptionEntry.where(date: Date.current).count).to eq(2)
      end
    end
  end
end
