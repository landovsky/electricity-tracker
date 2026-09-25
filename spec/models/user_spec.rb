require 'rails_helper'

RSpec.describe User, type: :model do
  describe "associations" do
    it { should have_many(:meter_reading_events).with_foreign_key(:recorded_by_user_id).dependent(:nullify) }
    it { should have_many(:manual_consumption_entries).with_foreign_key(:recorded_by_user_id).dependent(:nullify) }
  end

  describe "validations" do
    subject { described_class.new(email: "test@example.com", name: "Test User", role: "member") }

    it { should validate_presence_of(:role) }
    it { should validate_uniqueness_of(:email).allow_nil.ignoring_case_sensitivity }

    it "validates email format" do
      user = User.new(name: "Test", role: "member", email: "invalid")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    context "admin forms submit empty strings for fields left blank" do
      it "stores blank email and phone as nil so uniqueness (which only skips nil) never trips" do
        user = User.create!(name: "SMS", role: "member", email: " ", phone_number: "+420777000111")
        other = User.create!(name: "Mail", role: "member", email: "a@example.com", phone_number: "")
        another = User.create!(name: "Mail 2", role: "member", email: "b@example.com", phone_number: "")

        expect(user.email).to be_nil
        expect([ other.phone_number, another.phone_number ]).to all(be_nil)
      end

      it "downcases emails because login looks them up downcased" do
        user = User.create!(name: "Mixed", role: "member", email: " Mixed@Example.COM ")

        expect(user.email).to eq("mixed@example.com")
      end
    end

    it "accepts valid email format" do
      user = User.new(name: "Test", role: "member", email: "valid@example.com")
      expect(user).to be_valid
    end
  end

  describe "enums" do
    it { should define_enum_for(:role).backed_by_column_of_type(:string).with_values(member: "member", admin: "admin") }

    it "validates enum values" do
      user = User.new(name: "Test", email: "test@example.com", role: "invalid")
      expect(user).not_to be_valid
      expect(user.errors[:role]).to be_present
    end
  end

  describe "soft deletes" do
    it "includes Discard::Model" do
      expect(User.included_modules).to include(Discard::Model)
    end
  end
end
