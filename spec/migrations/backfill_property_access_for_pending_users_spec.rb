# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260925120000_backfill_property_access_for_pending_users")

# Logins stopped granting property access, so users an admin created before
# that change — who never logged in — were left without any PropertyUser and
# would be locked out on their first login (prod: user 7, visitor 13, property 1).
RSpec.describe BackfillPropertyAccessForPendingUsers do
  let(:property) { create(:property) }

  def run_migration
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  # A user as admin-created before the change: has a name and a visitor on the
  # property, but no property_users row (the membership callback never ran).
  def pending_user(visitor_property: property, **attrs)
    visitor = create(:visitor, property: visitor_property)
    create(:user, default_visitor: visitor, **attrs)
  end

  context "an admin-created member who never logged in before logins stopped granting access" do
    let!(:user) { pending_user }

    it "grants the property their default visitor lives on so their first login is not a dead end" do
      run_migration

      expect(user.reload.properties).to contain_exactly(property)
    end

    it "reuses their existing visitor instead of creating a duplicate one on the property" do
      expect { run_migration }.not_to change(Visitor, :count)
      expect(user.reload.default_visitor.property).to eq(property)
    end

    it "is safe to run again (deploy retries, re-run migrations) without duplicating access" do
      run_migration

      expect { run_migration }.not_to change(PropertyUser, :count)
    end
  end

  context "a user who already has access to some property (possibly a different one after an admin move)" do
    let(:other_property) { create(:property) }
    let!(:user) { pending_user.tap { |u| PropertyUser.insert!({ user_id: u.id, property_id: other_property.id }) } }

    it "leaves their memberships untouched, since the admin decided where they belong" do
      run_migration

      expect(user.reload.properties).to contain_exactly(other_property)
    end
  end

  context "a user who was deleted (discarded)" do
    let!(:user) { pending_user(deleted_at: 1.day.ago) }

    it "does not get access back through the backfill" do
      run_migration

      expect(user.reload.properties).to be_empty
    end
  end

  context "the default visitor's property has been deleted" do
    let(:deleted_property) { create(:property, deleted_at: 1.day.ago) }
    let!(:user) { pending_user(visitor_property: deleted_property) }

    it "grants nothing, because a deleted property must not become reachable again" do
      run_migration

      expect(user.reload.properties).to be_empty
    end
  end

  context "a self-registered user with no visitor yet (still has to finish onboarding)" do
    let!(:user) { create(:user, :not_onboarded) }

    it "grants nothing, leaving property assignment to onboarding" do
      run_migration

      expect(user.reload.properties).to be_empty
    end
  end
end
