FactoryBot.define do
  factory :meter_reading_event do
    recorded_at { Time.zone.now }
    event_type { "check_in" }
    association :recorded_by_user, factory: :user
    note { FFaker::Lorem.sentence }

    trait :check_in do
      event_type { "check_in" }
    end

    trait :check_out do
      event_type { "check_out" }
    end

    # Transient attribute to automatically create meter readings
    transient do
      property { nil }
      main_reading { nil }
      secondary_reading { nil }
    end

    after(:create) do |event, evaluator|
      if evaluator.property
        # Create main meter reading if value provided
        if evaluator.main_reading
          main_meter = evaluator.property.meters.find_or_create_by!(meter_type: "main") do |m|
            m.label = "Main meter"
            m.unit = "kWh"
          end
          create(:meter_reading, meter_reading_event: event, meter: main_meter, value_kwh: evaluator.main_reading)
        end

        # Create secondary meter reading if value provided
        if evaluator.secondary_reading
          secondary_meter = evaluator.property.meters.find_or_create_by!(meter_type: "secondary") do |m|
            m.label = "Upper floor meter"
            m.unit = "kWh"
          end
          create(:meter_reading, meter_reading_event: event, meter: secondary_meter, value_kwh: evaluator.secondary_reading)
        end
      end
    end
  end
end
