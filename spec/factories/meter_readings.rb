FactoryBot.define do
  factory :meter_reading do
    association :meter_reading_event
    association :meter

    # Sequence to ensure monotonic increases (C1 constraint)
    sequence(:value_kwh) { |n| 1000.0 + (n * 10.5) }
  end
end
