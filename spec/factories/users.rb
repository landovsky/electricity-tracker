FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { FFaker::Name.name }
    role { "member" }

    trait :admin do
      role { "admin" }
    end

    trait :member do
      role { "member" }
    end

    trait :with_phone do
      sequence(:phone_number) { |n| "+420777%06d" % n }
    end

    trait :phone_only do
      email { nil }
      sequence(:phone_number) { |n| "+420777%06d" % n }
    end

    trait :not_onboarded do
      name { nil }
    end
  end
end
