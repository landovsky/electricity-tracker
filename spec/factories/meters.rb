FactoryBot.define do
  factory :meter do
    association :property
    meter_type { "main" }
    label { "Main meter" }
    unit { "kWh" }
    meter_group { nil }

    trait :main do
      meter_type { "main" }
      label { "Main meter" }
    end

    trait :secondary do
      meter_type { "secondary" }
      label { "Upper floor meter" }
    end

    trait :main_vt do
      meter_type { "main" }
      label { "Main - VT" }
      meter_group { "main" }
    end

    trait :main_nt do
      meter_type { "main" }
      label { "Main - NT" }
      meter_group { "main" }
    end
  end
end
