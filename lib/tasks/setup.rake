# frozen_string_literal: true

namespace :app do
  desc "Set up essential production data (property, meters, users, visitors, stays). Idempotent."
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
    vt = Meter.find_or_create_by!(property: property, label: "Hlavní - VT") do |m|
      m.meter_type = "main"
      m.meter_group = "main"
      m.unit = "kWh"
      puts "  Created meter: #{m.label}"
    end

    nt = Meter.find_or_create_by!(property: property, label: "Hlavní - NT") do |m|
      m.meter_type = "main"
      m.meter_group = "main"
      m.unit = "kWh"
      puts "  Created meter: #{m.label}"
    end

    garage = Meter.find_or_create_by!(property: property, label: "Elektroměr garáž") do |m|
      m.meter_type = "secondary"
      m.unit = "kWh"
      puts "  Created meter: #{m.label}"
    end

    # --- Visitors ---
    visitor_names = %w[Tereza Jirka Johana Kristina Petr Tomáš]
    visitors = visitor_names.index_with do |name|
      Visitor.find_or_create_by!(property: property, name: name) do |v|
        v.status = "active"
        puts "  Created visitor: #{v.name}"
      end
    end

    # --- Users ---
    user_map = {
      "Tereza" => { email: "tereza.landovska@gmail.com", role: "member" },
      "Jirka" => { email: "cerny649@seznam.cz", role: "member" },
      "Johana" => { email: "johana.potuznikova@gmail.com", role: "member" },
      "Kristina" => { email: "kristina.djakoualnova@seznam.cz", role: "member" },
      "Petr" => { email: "potuznik@volny.cz", role: "member" },
      "Tomáš" => { email: "landovsky@gmail.com", role: "admin" }
    }

    user_map.each do |visitor_name, attrs|
      user = User.find_or_create_by!(email: attrs[:email]) do |u|
        u.name = visitor_name
        u.role = attrs[:role]
        puts "  Created user: #{u.email} (#{attrs[:role]})"
      end
      user.update!(default_visitor: visitors[visitor_name]) if user.default_visitor != visitors[visitor_name]
      PropertyUser.find_or_create_by!(property: property, user: user)
    end

    # --- Initial meter readings (19 Sep 2025) ---
    if MeterReadingEvent.where(event_type: "initial").none?
      initial_date = Time.zone.parse("2025-09-19 08:00")
      event = MeterReadingEvent.create!(event_type: "initial", recorded_at: initial_date)
      event.meter_readings.create!(meter: vt, value_kwh: 86_740)
      event.meter_readings.create!(meter: nt, value_kwh: 123_733)
      event.meter_readings.create!(meter: garage, value_kwh: 1934)
      puts "  Created initial readings: VT=86740, NT=123733, Garáž=1934"
    end

    # --- Stays and meter reading events ---
    # Skip if stays already exist
    if Stay.count.zero?
      # Helper to create a check-in/check-out event with readings
      create_event = lambda do |type, date_str, vt_val, nt_val, garage_val|
        event = MeterReadingEvent.create!(
          event_type: type,
          recorded_at: Time.zone.parse(date_str)
        )
        event.meter_readings.create!(meter: vt, value_kwh: vt_val) if vt_val
        event.meter_readings.create!(meter: nt, value_kwh: nt_val) if nt_val
        event.meter_readings.create!(meter: garage, value_kwh: garage_val) if garage_val
        event
      end

      # Visits 1+2: Jirka & Kristina 19.9.25 - 21.9.25 (concurrent)
      # Create both check-ins first, then check-outs (to satisfy monotonic validation)
      ci_jirka = create_event.call("check_in", "2025-09-19 12:00", 86_740, 123_733, 1934)
      ci_kristina = create_event.call("check_in", "2025-09-19 12:01", 86_740, 123_735, nil)
      co_jirka = create_event.call("check_out", "2025-09-21 12:00", 86_744, 123_772, 1951)
      co_kristina = create_event.call("check_out", "2025-09-21 12:01", 86_744, 123_772, nil)
      Stay.create!(visitor: visitors["Jirka"], property: property, check_in_event: ci_jirka, check_out_event: co_jirka)
      Stay.create!(visitor: visitors["Kristina"], property: property, check_in_event: ci_kristina, check_out_event: co_kristina)
      puts "  Stay: Jirka 19.9 - 21.9.25"
      puts "  Stay: Kristina 19.9 - 21.9.25"

      # Visit 3: Jirka 9.10.25 - 12.10.25
      ci = create_event.call("check_in", "2025-10-09 12:00", 86_744, 123_773, 1951)
      co = create_event.call("check_out", "2025-10-12 12:00", 86_754, 123_842, 2029)
      Stay.create!(visitor: visitors["Jirka"], property: property, check_in_event: ci, check_out_event: co)
      puts "  Stay: Jirka 9.10 - 12.10.25"

      # Visit 4: Tereza 17.11.25 - 20.11.25
      ci = create_event.call("check_in", "2025-11-17 12:00", 86_754, 123_842, 2029)
      co = create_event.call("check_out", "2025-11-20 12:00", 86_761, 123_901, 2029)
      Stay.create!(visitor: visitors["Tereza"], property: property, check_in_event: ci, check_out_event: co)
      puts "  Stay: Tereza 17.11 - 20.11.25"

      # Visit 5: Petr 19.1.26 - 20.1.26
      ci = create_event.call("check_in", "2026-01-19 12:00", 86_761, 123_901, 2029)
      co = create_event.call("check_out", "2026-01-20 12:00", 86_773, 123_995, 2029)
      Stay.create!(visitor: visitors["Petr"], property: property, check_in_event: ci, check_out_event: co)
      puts "  Stay: Petr 19.1 - 20.1.26"

      # Visit 6: Tereza 30.1.26 - 1.2.26
      ci = create_event.call("check_in", "2026-01-30 12:00", 86_773, 123_995, 2029)
      co = create_event.call("check_out", "2026-02-01 12:00", 86_789, 124_122, 2029)
      Stay.create!(visitor: visitors["Tereza"], property: property, check_in_event: ci, check_out_event: co)
      puts "  Stay: Tereza 30.1 - 1.2.26"

      # Visit 7: Tereza 2.4.26 - open
      ci = create_event.call("check_in", "2026-04-02 12:00", 86_789, 124_123, 2029)
      Stay.create!(visitor: visitors["Tereza"], property: property, check_in_event: ci)
      puts "  Stay: Tereza 2.4.26 (open)"

      # Visit 8: Johana 4.4.26 - open
      ci = create_event.call("check_in", "2026-04-04 12:00", 86_809, 124_235, 2029)
      Stay.create!(visitor: visitors["Johana"], property: property, check_in_event: ci)
      puts "  Stay: Johana 4.4.26 (open)"
    end

    # --- Manual consumption entry ---
    if ManualConsumptionEntry.count.zero?
      ManualConsumptionEntry.create!(
        visitor: visitors["Tereza"],
        property: property,
        date: Date.parse("2026-04-04"),
        kwh: 47,
        note: "nabíjení"
      )
      puts "  Manual entry: Tereza 4.4.26, 47 kWh (nabíjení)"
    end

    puts "Setup complete."
    puts "  Property: #{property.name}, Meters: #{Meter.count}"
    puts "  Users: #{User.count}, Visitors: #{Visitor.count}"
    puts "  Stays: #{Stay.count}, Events: #{MeterReadingEvent.count}"
    puts "  Manual entries: #{ManualConsumptionEntry.count}"
  end
end
