require 'rails_helper'

RSpec.describe Property, type: :model do
  describe "associations" do
    it { should have_many(:meters).dependent(:destroy) }
    it { should have_many(:stays).dependent(:destroy) }
    it { should have_many(:manual_consumption_entries).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:name) }
  end

  describe "soft deletes" do
    it "includes Discard::Model" do
      expect(Property.included_modules).to include(Discard::Model)
    end

    it "soft deletes the property" do
      property = Property.create!(name: "Family House")
      property.discard
      expect(property.discarded?).to be true
      expect(Property.kept.where(id: property.id)).to be_empty
    end
  end
end
