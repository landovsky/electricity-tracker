# frozen_string_literal: true

namespace :app do
  desc "Set up essential production data (property, meters, users, visitors). Idempotent."
  task setup: :environment do
    puts "Setting up essential data..."

    # --- Property ---
    property = Property.find_or_create_by!(name: "Suchá") do |p|
      p.subdomain = "sepot"
      p.tracking_mode = "visitors"
      p.address = "Horní Planá"
      puts "  Created property: #{p.name}"
    end

    # --- Meters ---
    garage = Meter.find_or_create_by!(property: property, label: "Elektroměr garáž") do |m|
      m.meter_type = "secondary"
      m.unit = "kWh"
      puts "  Created meter: #{m.label}"
    end

    hlavni_nt = Meter.find_or_create_by!(property: property, label: "Hlavní - NT") do |m|
      m.meter_type = "main"
      m.meter_group = "main"
      m.unit = "kWh"
      puts "  Created meter: #{m.label}"
    end

    hlavni_vt = Meter.find_or_create_by!(property: property, label: "Hlavní - VT") do |m|
      m.meter_type = "main"
      m.meter_group = "main"
      m.unit = "kWh"
      puts "  Created meter: #{m.label}"
    end

    # --- Initial meter readings (19 Jan 2026) ---
    initial_date = Time.zone.parse("2026-01-19")
    initial_readings = {
      garage => 2029,
      hlavni_nt => 123_901,
      hlavni_vt => 86_761
    }

    initial_readings.each do |meter, value|
      existing = meter.meter_readings.joins(:meter_reading_event)
                      .where(meter_reading_events: { event_type: "initial" })
                      .exists?
      next if existing

      event = MeterReadingEvent.create!(
        event_type: "initial",
        recorded_at: initial_date
      )
      event.meter_readings.create!(meter: meter, value_kwh: value)
      puts "  Created initial reading for #{meter.label}: #{value} kWh"
    end

    # --- Visitors ---
    tomas_visitor = Visitor.find_or_create_by!(property: property, name: "Tomáš") do |v|
      v.status = "active"
      puts "  Created visitor: #{v.name}"
    end

    petr_visitor = Visitor.find_or_create_by!(property: property, name: "Petr") do |v|
      v.status = "active"
      puts "  Created visitor: #{v.name}"
    end

    # --- Users ---
    tomas_user = User.find_or_create_by!(email: "tomas@kopernici.cz") do |u|
      u.name = "Tomáš"
      u.role = "admin"
      puts "  Created admin user: #{u.email}"
    end
    tomas_user.update!(default_visitor: tomas_visitor) if tomas_user.default_visitor != tomas_visitor

    petr_user = User.find_or_create_by!(email: "potuznik@volny.cz") do |u|
      u.name = "Petr"
      u.role = "member"
      puts "  Created user: #{u.email}"
    end
    petr_user.update!(default_visitor: petr_visitor) if petr_user.default_visitor != petr_visitor

    # --- Property-User associations ---
    PropertyUser.find_or_create_by!(property: property, user: tomas_user)
    PropertyUser.find_or_create_by!(property: property, user: petr_user)

    puts "Setup complete. Property: #{property.name}, Meters: #{Meter.count}, Users: #{User.count}, Visitors: #{Visitor.count}"
  end
end
