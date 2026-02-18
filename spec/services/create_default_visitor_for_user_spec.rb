# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateDefaultVisitorForUser, type: :service do
  let(:user) { create(:user, name: "Jan Novak") }

  describe "happy path" do
    it "creates a Visitor with the user's name and active status" do
      outcome = described_class.run(user: user)

      expect(outcome).to be_valid
      visitor = outcome.result
      expect(visitor).to be_a(Visitor)
      expect(visitor).to be_persisted
      expect(visitor.name).to eq("Jan Novak")
      expect(visitor.status).to eq("active")
    end

    it "sets default_visitor_id on the user" do
      outcome = described_class.run(user: user)

      visitor = outcome.result
      expect(user.reload.default_visitor_id).to eq(visitor.id)
    end

    it "returns the new visitor" do
      outcome = described_class.run(user: user)

      expect(outcome.result).to be_a(Visitor)
    end
  end

  describe "idempotency" do
    it "does not create a second Visitor if user already has a default_visitor" do
      existing_visitor = create(:visitor, name: user.name)
      user.update_column(:default_visitor_id, existing_visitor.id)

      expect {
        described_class.run(user: user)
      }.not_to change(Visitor, :count)
    end

    it "returns the existing default_visitor when called again" do
      existing_visitor = create(:visitor, name: user.name)
      user.update_column(:default_visitor_id, existing_visitor.id)

      # Reload association so it's fresh
      user.reload

      outcome = described_class.run(user: user)
      expect(outcome.result).to eq(existing_visitor)
    end
  end

  describe "error handling" do
    it "adds an error if Visitor creation fails" do
      allow(Visitor).to receive(:create!).and_raise(
        ActiveRecord::RecordInvalid.new(Visitor.new.tap { |v| v.errors.add(:name, "is invalid") })
      )

      outcome = described_class.run(user: user)

      expect(outcome).not_to be_valid
      expect(outcome.errors[:base]).to be_present
    end
  end
end
