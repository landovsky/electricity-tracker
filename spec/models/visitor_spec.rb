require 'rails_helper'

RSpec.describe Visitor, type: :model do
  describe "associations" do
    it { should have_many(:stays).dependent(:destroy) }
    it { should have_many(:manual_consumption_entries).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:status) }
  end

  describe "enums" do
    it { should define_enum_for(:status).backed_by_column_of_type(:string).with_values(active: "active", archived: "archived") }

    it "validates enum values" do
      visitor = Visitor.new(name: "Test", status: "invalid")
      expect(visitor).not_to be_valid
      expect(visitor.errors[:status]).to be_present
    end
  end

  describe "scopes" do
    before do
      property = create(:property)
      property.visitors.create!(name: "Active Visitor", status: "active")
      property.visitors.create!(name: "Archived Visitor", status: "archived")
    end

    describe ".active" do
      it "returns only active visitors" do
        expect(Visitor.active.count).to eq(1)
        expect(Visitor.active.first.status).to eq("active")
      end
    end

    describe ".archived" do
      it "returns only archived visitors" do
        expect(Visitor.archived.count).to eq(1)
        expect(Visitor.archived.first.status).to eq("archived")
      end
    end
  end

  describe "soft deletes" do
    it "includes Discard::Model" do
      expect(Visitor.included_modules).to include(Discard::Model)
    end
  end
end
