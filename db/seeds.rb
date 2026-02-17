# frozen_string_literal: true

# Seed data for development environment
# This file is idempotent and can be run multiple times without creating duplicates

# Only seed in development environment
return unless Rails.env.development?

puts "🌱 Seeding development database..."

# =============================================================================
# PROPERTY & METERS
# =============================================================================

property = Property.find_or_create_by!(name: "Family House") do |p|
  p.address = "Horní Planá 123, 382 26 Horní Planá"
  puts "✓ Created property: #{p.name}"
end

main_meter = Meter.find_or_create_by!(property: property, meter_type: "main") do |m|
  m.label = "Main Meter"
  m.unit = "kWh"
  puts "✓ Created meter: #{m.label}"
end

secondary_meter = Meter.find_or_create_by!(property: property, meter_type: "secondary") do |m|
  m.label = "Secondary Meter"
  m.unit = "kWh"
  puts "✓ Created meter: #{m.label}"
end

# =============================================================================
# USERS
# =============================================================================

admin = User.find_or_create_by!(email: "admin@familyhouse.example") do |u|
  u.name = "Admin User"
  u.role = "admin"
  puts "✓ Created user: #{u.name} (#{u.role})"
end

member = User.find_or_create_by!(email: "member@familyhouse.example") do |u|
  u.name = "Regular Member"
  u.role = "member"
  puts "✓ Created user: #{u.name} (#{u.role})"
end

# =============================================================================
# VISITORS
# =============================================================================

petr = Visitor.find_or_create_by!(name: "Petr Potužník") do |v|
  v.status = "active"
  puts "✓ Created visitor: #{v.name}"
end

tereza = Visitor.find_or_create_by!(name: "Tereza") do |v|
  v.status = "active"
  puts "✓ Created visitor: #{v.name}"
end

bara = Visitor.find_or_create_by!(name: "Bára") do |v|
  v.status = "active"
  puts "✓ Created visitor: #{v.name}"
end

# =============================================================================
# SAMPLE STAYS & METER READINGS
# =============================================================================

# Helper method to create stays if they don't exist
def create_sample_stay(visitor:, property:, user:, check_in_time:, check_out_time:, main_reading_in:, main_reading_out:, secondary_reading_in:, secondary_reading_out:, note_in: nil, note_out: nil)
  # Check if visitor already has a stay around this time
  existing_stay = visitor.stays.find_by("created_at >= ? AND created_at <= ?", check_in_time - 1.hour, check_in_time + 1.hour)
  return if existing_stay

  # Check-in
  check_in_result = CheckInVisitor.run(
    property: property,
    visitor: visitor,
    recorded_by_user: user,
    recorded_at: check_in_time,
    main_meter_reading: main_reading_in,
    secondary_meter_reading: secondary_reading_in,
    note: note_in
  )

  if check_in_result.valid?
    stay = check_in_result.result
    puts "  ✓ Checked in #{visitor.name} (#{check_in_time.strftime('%b %d, %H:%M')}, meter: #{main_reading_in}/#{secondary_reading_in} kWh)"

    # Check-out (if specified)
    if check_out_time
      check_out_result = CheckOutVisitor.run(
        stay: stay,
        property: property,
        recorded_by_user: user,
        recorded_at: check_out_time,
        main_meter_reading: main_reading_out,
        secondary_meter_reading: secondary_reading_out,
        note: note_out
      )

      if check_out_result.valid?
        puts "  ✓ Checked out #{visitor.name} (#{check_out_time.strftime('%b %d, %H:%M')}, meter: #{main_reading_out}/#{secondary_reading_out} kWh)"
      else
        puts "  ✗ Failed to check out #{visitor.name}: #{check_out_result.errors.full_messages.join(', ')}"
      end
    end
  else
    puts "  ✗ Failed to check in #{visitor.name}: #{check_in_result.errors.full_messages.join(', ')}"
  end
end

puts "\n📅 Creating sample stays..."

# Starting meter readings: Main 15420 kWh, Secondary 8200 kWh

# January: Petr stayed for a week
create_sample_stay(
  visitor: petr,
  property: property,
  user: admin,
  check_in_time: 45.days.ago.change(hour: 16, min: 30),
  check_out_time: 38.days.ago.change(hour: 11, min: 0),
  main_reading_in: 15420.0,
  main_reading_out: 15598.0,  # 178 kWh over 7 days (winter heating)
  secondary_reading_in: 8200.0,
  secondary_reading_out: 8245.0,  # 45 kWh
  note_in: "Zimní pobyt, topení bude potřeba",
  note_out: "Odjezd ráno"
)

# Late January: Tereza weekend visit
create_sample_stay(
  visitor: tereza,
  property: property,
  user: member,
  check_in_time: 30.days.ago.change(hour: 18, min: 0),
  check_out_time: 28.days.ago.change(hour: 14, min: 30),
  main_reading_in: 15598.0,
  main_reading_out: 15658.0,  # 60 kWh over 2 days
  secondary_reading_in: 8245.0,
  secondary_reading_out: 8265.0,  # 20 kWh
  note_in: "Weekend trip",
  note_out: nil
)

# Early February: Bára working week
create_sample_stay(
  visitor: bara,
  property: property,
  user: admin,
  check_in_time: 20.days.ago.change(hour: 14, min: 0),
  check_out_time: 15.days.ago.change(hour: 10, min: 0),
  main_reading_in: 15658.0,
  main_reading_out: 15800.0,  # 142 kWh over 5 days
  secondary_reading_in: 8265.0,
  secondary_reading_out: 8310.0,  # 45 kWh
  note_in: "Pracovní týden na chalupě",
  note_out: "Všechno vypnuto a zamčeno"
)

# Mid February: Create overlapping stays by managing events in chronological order
# We'll create: Tereza check-in -> Petr check-in -> Tereza check-out -> Petr still there

# Day 1: Tereza checks in (10 days ago, Friday evening)
tereza_checkin = CheckInVisitor.run(
  property: property,
  visitor: tereza,
  recorded_by_user: member,
  recorded_at: 10.days.ago.change(hour: 18, min: 0),
  main_meter_reading: 15800.0,
  secondary_meter_reading: 8310.0,
  note: "Víkendový pobyt"
)
if tereza_checkin.valid?
  puts "  ✓ Checked in Tereza (#{10.days.ago.strftime('%b %d, %H:%M')}, meter: 15800.0/8310.0 kWh)"
  tereza_stay = tereza_checkin.result
end

# Day 2: Petr checks in (9 days ago, Saturday morning) - OVERLAP STARTS
petr_checkin = CheckInVisitor.run(
  property: property,
  visitor: petr,
  recorded_by_user: admin,
  recorded_at: 9.days.ago.change(hour: 10, min: 30),
  main_meter_reading: 15830.0,
  secondary_meter_reading: 8318.0,
  note: "Přijíždím na prodloužený víkend"
)
if petr_checkin.valid?
  puts "  ✓ Checked in Petr Potužník (#{9.days.ago.strftime('%b %d, %H:%M')}, meter: 15830.0/8318.0 kWh)"
  petr_stay = petr_checkin.result
end

# Day 3: Tereza checks out (7 days ago, Monday afternoon) - OVERLAP ENDS
if tereza_stay
  tereza_checkout = CheckOutVisitor.run(
    stay: tereza_stay,
    property: property,
    recorded_by_user: member,
    recorded_at: 7.days.ago.change(hour: 14, min: 0),
    main_meter_reading: 15920.0,
    secondary_meter_reading: 8340.0,
    note: "Byl to super víkend!"
  )
  if tereza_checkout.valid?
    puts "  ✓ Checked out Tereza (#{7.days.ago.strftime('%b %d, %H:%M')}, meter: 15920.0/8340.0 kWh)"
  end
end

# Petr is still here (stay remains open)
if petr_stay
  puts "  ✓ Petr Potužník still at the house (checked in #{9.days.ago.strftime('%b %d')})"
end

# =============================================================================
# SAMPLE MANUAL CONSUMPTION ENTRIES
# =============================================================================

puts "\n⚡ Creating sample manual consumption entries..."

# Helper method to create manual entries if they don't exist
def create_manual_entry(visitor:, property:, user:, date:, kwh:, note:)
  # Check if entry already exists for this visitor on this date
  existing_entry = visitor.manual_consumption_entries.find_by(date: date)
  return if existing_entry

  result = CreateManualConsumptionEntry.run(
    visitor: visitor,
    property: property,
    recorded_by_user: user,
    date: date,
    kwh: kwh,
    note: note
  )

  if result.valid?
    puts "  ✓ Manual entry for #{visitor.name} (#{date}): #{kwh} kWh - #{note}"
  else
    puts "  ✗ Failed to create manual entry: #{result.errors.full_messages.join(', ')}"
  end
end

# Petr charged his electric car during his January stay
create_manual_entry(
  visitor: petr,
  property: property,
  user: admin,
  date: 42.days.ago.to_date,
  kwh: 45.0,
  note: "Nabití elektroauta (Škoda Enyaq)"
)

# Tereza used heating intensively during winter weekend
create_manual_entry(
  visitor: tereza,
  property: property,
  user: member,
  date: 29.days.ago.to_date,
  kwh: 28.0,
  note: "Extra topení - byla zima"
)

# Bára worked from home and used laptop + monitors continuously
create_manual_entry(
  visitor: bara,
  property: property,
  user: admin,
  date: 18.days.ago.to_date,
  kwh: 15.5,
  note: "Home office setup - monitor + laptop celý týden"
)

# Tereza's weekend heating usage
create_manual_entry(
  visitor: tereza,
  property: property,
  user: member,
  date: 9.days.ago.to_date,
  kwh: 22.0,
  note: "Intenzivní topení přes víkend"
)

# Petr's EV charging during current stay
create_manual_entry(
  visitor: petr,
  property: property,
  user: admin,
  date: 8.days.ago.to_date,
  kwh: 48.5,
  note: "Nabití elektroauta - Škoda Enyaq"
)

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n✅ Seed data created successfully!"
puts "   • #{Property.count} property"
puts "   • #{Meter.count} meters"
puts "   • #{User.count} users"
puts "   • #{Visitor.count} visitors"
puts "   • #{Stay.count} stays (#{Stay.open.count} open, #{Stay.closed.count} closed)"
puts "   • #{MeterReadingEvent.count} meter reading events"
puts "   • #{ManualConsumptionEntry.count} manual consumption entries"
puts "\n🔐 Login credentials:"
puts "   • Admin: admin@familyhouse.example"
puts "   • Member: member@familyhouse.example"
puts "\n💡 You can run 'rails db:seed' again safely - it's idempotent!"
puts "\n📊 Current status:"
if Stay.open.any?
  Stay.open.each do |stay|
    puts "   • #{stay.visitor.name} is currently at the house (since #{stay.check_in_event.recorded_at.strftime('%b %d')})"
  end
else
  puts "   • No one is currently at the house"
end
