FactoryBot.define do
  factory :stay do
    association :visitor
    association :property
    note { FFaker::Lorem.sentence }

    # Transient attributes for flexible stay creation
    transient do
      check_in_at { 2.days.ago }
      check_out_at { nil }
      main_reading_in { 1000.0 }
      secondary_reading_in { 500.0 }
      main_reading_out { nil }
      secondary_reading_out { nil }
      recorded_by { nil }
    end

    # Create meters and check-in event after the stay is created
    after(:create) do |stay, evaluator|
      # Ensure property has meters
      main_meter = stay.property.meters.find_or_create_by!(meter_type: "main") do |m|
        m.label = "Main meter"
        m.unit = "kWh"
      end

      secondary_meter = stay.property.meters.find_or_create_by!(meter_type: "secondary") do |m|
        m.label = "Upper floor meter"
        m.unit = "kWh"
      end

      # Create check-in event with meter readings if not already set
      unless stay.check_in_event
        user = evaluator.recorded_by || create(:user)

        check_in_event = create(:meter_reading_event,
          event_type: "check_in",
          recorded_at: evaluator.check_in_at,
          recorded_by_user: user
        )

        create(:meter_reading,
          meter_reading_event: check_in_event,
          meter: main_meter,
          value_kwh: evaluator.main_reading_in
        )

        create(:meter_reading,
          meter_reading_event: check_in_event,
          meter: secondary_meter,
          value_kwh: evaluator.secondary_reading_in
        )

        stay.update!(check_in_event: check_in_event)
      end
    end

    trait :open do
      # Default behavior - no check_out_event
      check_out_event { nil }
    end

    trait :closed do
      transient do
        check_out_at { 1.day.ago }
        main_reading_out { 1050.0 }
        secondary_reading_out { 525.0 }
      end

      after(:create) do |stay, evaluator|
        # Create check-out event with meter readings
        unless stay.check_out_event
          user = evaluator.recorded_by || stay.check_in_event&.recorded_by_user || create(:user)

          main_meter = stay.property.meters.find_by!(meter_type: "main")
          secondary_meter = stay.property.meters.find_by!(meter_type: "secondary")

          check_out_event = create(:meter_reading_event,
            event_type: "check_out",
            recorded_at: evaluator.check_out_at,
            recorded_by_user: user
          )

          create(:meter_reading,
            meter_reading_event: check_out_event,
            meter: main_meter,
            value_kwh: evaluator.main_reading_out
          )

          create(:meter_reading,
            meter_reading_event: check_out_event,
            meter: secondary_meter,
            value_kwh: evaluator.secondary_reading_out
          )

          stay.update!(check_out_event: check_out_event)
        end
      end
    end
  end
end
