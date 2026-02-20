# frozen_string_literal: true

# Join model linking users to properties they are allowed to access.
# TODO: Replace checkbox UI with a scalable search/select when user count grows.
class PropertyUser < ApplicationRecord
  belongs_to :property
  belongs_to :user

  validates :property_id, uniqueness: { scope: :user_id }
end
