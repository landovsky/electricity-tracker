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
  p.note = "Main family property in the countryside"
  puts "✓ Created property: #{p.name}"
end

main_meter = Meter.find_or_create_by!(property: property, meter_type: "main") do |m|
  m.label = "Main Meter"
  m.note = "Primary electricity meter for the house"
  puts "✓ Created meter: #{m.label}"
end

secondary_meter = Meter.find_or_create_by!(property: property, meter_type: "secondary") do |m|
  m.label = "Solar Panel Meter"
  m.note = "Meter for solar panel generation"
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

alice = Visitor.find_or_create_by!(name: "Alice Johnson") do |v|
  v.status = "active"
  v.note = "Family member, visits frequently"
  puts "✓ Created visitor: #{v.name}"
end

bob = Visitor.find_or_create_by!(name: "Bob Smith") do |v|
  v.status = "active"
  v.note = "Friend of the family"
  puts "✓ Created visitor: #{v.name}"
end

charlie = Visitor.find_or_create_by!(name: "Charlie Davis") do |v|
  v.status = "active"
  v.note = "Weekend guest"
  puts "✓ Created visitor: #{v.name}"
end

diana = Visitor.find_or_create_by!(name: "Diana Martinez") do |v|
  v.status = "active"
  v.note = "Summer visitor"
  puts "✓ Created visitor: #{v.name}"
end

# =============================================================================
# SAMPLE STAYS & METER READINGS
# =============================================================================

# Helper method to create stays if they don't exist
def create_sample_stay(visitor:, property:, user:, check_in_days_ago:, check_out_days_ago:, main_reading_in:, main_reading_out:, secondary_reading_in:, secondary_reading_out:)
  # Check if visitor already has a stay in this time range
  existing_stay = visitor.stays.find_by("created_at >= ?", (check_in_days_ago + 1).days.ago)
  return if existing_stay

  # Check-in
  check_in_result = CheckInVisitor.run(
    property: property,
    visitor: visitor,
    recorded_by_user: user,
    recorded_at: check_in_days_ago.days.ago,
    main_meter_reading: main_reading_in,
    secondary_meter_reading: secondary_reading_in,
    note: "Seed data check-in"
  )

  if check_in_result.valid?
    stay = check_in_result.result
    puts "  ✓ Checked in #{visitor.name} (#{check_in_days_ago} days ago, meter: #{main_reading_in} kWh)"

    # Check-out (if specified)
    if check_out_days_ago
      check_out_result = CheckOutVisitor.run(
        stay: stay,
        property: property,
        recorded_by_user: user,
        recorded_at: check_out_days_ago.days.ago,
        main_meter_reading: main_reading_out,
        secondary_meter_reading: secondary_reading_out,
        note: "Seed data check-out"
      )

      if check_out_result.valid?
        puts "  ✓ Checked out #{visitor.name} (#{check_out_days_ago} days ago, meter: #{main_reading_out} kWh)"
      else
        puts "  ✗ Failed to check out #{visitor.name}: #{check_out_result.errors.full_messages.join(', ')}"
      end
    end
  else
    puts "  ✗ Failed to check in #{visitor.name}: #{check_in_result.errors.full_messages.join(', ')}"
  end
end

# Create sample stays (using services to ensure constraints are met)
puts "\n📅 Creating sample stays..."

# Alice: Completed stay 30-20 days ago
create_sample_stay(
  visitor: alice,
  property: property,
  user: admin,
  check_in_days_ago: 30,
  check_out_days_ago: 20,
  main_reading_in: 1000.0,
  main_reading_out: 1250.0,
  secondary_reading_in: 500.0,
  secondary_reading_out: 600.0
)

# Bob: Completed stay 19-10 days ago
create_sample_stay(
  visitor: bob,
  property: property,
  user: member,
  check_in_days_ago: 19,
  check_out_days_ago: 10,
  main_reading_in: 1250.0,
  main_reading_out: 1400.0,
  secondary_reading_in: 600.0,
  secondary_reading_out: 680.0
)

# Charlie: Completed stay 9-5 days ago
create_sample_stay(
  visitor: charlie,
  property: property,
  user: admin,
  check_in_days_ago: 9,
  check_out_days_ago: 5,
  main_reading_in: 1400.0,
  main_reading_out: 1500.0,
  secondary_reading_in: 680.0,
  secondary_reading_out: 740.0
)

# Diana: Currently checked in (4 days ago, still open)
create_sample_stay(
  visitor: diana,
  property: property,
  user: member,
  check_in_days_ago: 4,
  check_out_days_ago: nil,  # Still checked in
  main_reading_in: 1500.0,
  main_reading_out: nil,
  secondary_reading_in: 740.0,
  secondary_reading_out: nil
)

# =============================================================================
# SAMPLE MANUAL CONSUMPTION ENTRIES
# =============================================================================

puts "\n⚡ Creating sample manual consumption entries..."

# Helper method to create manual entries if they don't exist
def create_manual_entry(visitor:, property:, user:, days_ago:, kwh:, note:)
  # Check if entry already exists for this visitor on this date
  date = days_ago.days.ago.to_date
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
    puts "  ✓ Manual entry for #{visitor.name} (#{days_ago} days ago): #{kwh} kWh - #{note}"
  else
    puts "  ✗ Failed to create manual entry: #{result.errors.full_messages.join(', ')}"
  end
end

# Alice charged her EV during her stay
create_manual_entry(
  visitor: alice,
  property: property,
  user: admin,
  days_ago: 25,
  kwh: 75.0,
  note: "EV charging (Tesla Model 3)"
)

# Bob used power tools in the workshop
create_manual_entry(
  visitor: bob,
  property: property,
  user: member,
  days_ago: 15,
  kwh: 25.0,
  note: "Workshop tools (circular saw, drill)"
)

# Charlie ran a space heater
create_manual_entry(
  visitor: charlie,
  property: property,
  user: admin,
  days_ago: 7,
  kwh: 30.0,
  note: "Space heater in guest room"
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
