require 'rails_helper'

RSpec.describe PropertyUser, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:property) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject { create(:property_user) }

    it { is_expected.to validate_uniqueness_of(:property_id).scoped_to(:user_id) }
  end

  describe 'creation' do
    it 'creates a valid property_user' do
      property_user = create(:property_user)
      expect(property_user).to be_persisted
    end

    it 'prevents duplicate assignments' do
      property_user = create(:property_user)
      duplicate = build(:property_user, property: property_user.property, user: property_user.user)
      expect(duplicate).not_to be_valid
    end
  end
end
