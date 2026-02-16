FactoryBot.define do
  factory :meter do
    association :property
    meter_type { "main" }
    label { "Main meter" }
    unit { "kWh" }

    trait :main do
      meter_type { "main" }
      label { "Main meter" }
    end

    trait :secondary do
      meter_type { "secondary" }
      label { "Upper floor meter" }
    end
  end
end
