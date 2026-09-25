# frozen_string_literal: true

require "rails_helper"

RSpec.describe XlsDataMigration do
  let(:property) { create(:property, name: "Suchá", subdomain: "sepot") }
  let(:visitor) { create(:visitor, name: "Tereza", property: property) }
  let!(:stay) { create(:stay, visitor: visitor, property: property) }

  around do |example|
    original = ENV.fetch(described_class::OPT_IN_ENV, nil)
    example.run
  ensure
    ENV[described_class::OPT_IN_ENV] = original
  end

  before { allow($stdout).to receive(:puts) }

  context "the live database already holds stays and readings and nobody opted in" do
    before { ENV.delete(described_class::OPT_IN_ENV) }

    it "refuses before deleting anything, so an accidental click cannot wipe production" do
      expect { described_class.run }.to raise_error(described_class::Refused, /ALLOW_DESTRUCTIVE_XLS_MIGRATION/)

      expect(Stay.exists?(stay.id)).to be(true)
      expect(Property.exists?(property.id)).to be(true)
    end
  end

  context "the database has no tracked data yet (first import on a fresh environment)" do
    before do
      ENV.delete(described_class::OPT_IN_ENV)
      Stay.delete_all
      MeterReading.delete_all
      MeterReadingEvent.delete_all
    end

    it "is allowed without the opt-in, because there is nothing to lose" do
      expect(described_class.allowed?).to be(true)
    end
  end

  context "an admin opted in, but the import blows up after the wipe (e.g. unreadable XLS)" do
    before do
      ENV[described_class::OPT_IN_ENV] = "true"
      allow_any_instance_of(described_class).to receive(:parse_xls!).and_raise(IOError, "cannot read XLS")
    end

    it "rolls the wipe back with the failed import, so production is not left empty" do
      member = create(:user, role: "member")
      create(:property_user, property: property, user: member)

      expect { described_class.run }.to raise_error(IOError)

      expect(Property.where(id: property.id, subdomain: "sepot")).to exist
      expect(Stay.exists?(stay.id)).to be(true)
      expect(MeterReadingEvent.count).to be > 0
      expect(User.exists?(member.id)).to be(true)
      expect(PropertyUser.where(property: property, user: member)).to exist
    end
  end

  context "an admin deliberately opted in to replace live data with the XLS history" do
    before { ENV[described_class::OPT_IN_ENV] = "true" }

    it "replaces the data without leaving rows that point at deleted records" do
      member = create(:user, role: "member")
      create(:property_user, property: property, user: member)
      admin = create(:user, :admin)
      admin.update_column(:default_visitor_id, visitor.id)

      described_class.run

      expect(Property.where(id: property.id)).not_to exist
      expect(PropertyUser.where(property_id: property.id)).not_to exist
      expect(User.exists?(member.id)).to be(false)
      expect(admin.reload.default_visitor_id).to be_nil
      expect(ActiveRecord::Base.connection.select_rows("PRAGMA foreign_key_check")).to be_empty
      expect(Property.sole.subdomain).to eq("sepot")
    end
  end
end
