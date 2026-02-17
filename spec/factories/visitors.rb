FactoryBot.define do
  factory :visitor do
    name { FFaker::Name.name }
    status { "active" }
    note { FFaker::Lorem.sentence }

    trait :active do
      status { "active" }
    end

    trait :archived do
      status { "archived" }
    end

    trait :discarded do
      deleted_at { Time.current }
    end
  end
end
