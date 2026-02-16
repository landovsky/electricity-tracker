FactoryBot.define do
  factory :manual_consumption_entry do
    association :visitor
    association :property
    association :recorded_by_user, factory: :user
    date { Date.current }
    kwh { rand(5.0..50.0).round(2) }
    note { "#{FFaker::Lorem.words(2).join(' ').capitalize} - #{kwh} kWh" }
  end
end
