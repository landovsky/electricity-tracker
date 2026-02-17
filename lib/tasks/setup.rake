# frozen_string_literal: true

namespace :app do
  desc "Set up essential production data (property, meters, admin user). Idempotent."
  task setup: :environment do
    puts "Setting up essential data..."

    property = Property.find_or_create_by!(name: "Suchá") do |p|
      p.address = "Horní Planá"
      puts "  Created property: #{p.name}"
    end

    Meter.find_or_create_by!(property: property, meter_type: "main") do |m|
      m.label = "Main Meter"
      m.unit = "kWh"
      puts "  Created meter: #{m.label}"
    end

    Meter.find_or_create_by!(property: property, meter_type: "secondary") do |m|
      m.label = "Secondary Meter"
      m.unit = "kWh"
      puts "  Created meter: #{m.label}"
    end

    admin_email = ENV.fetch("ADMIN_EMAIL", "tomas@kopernici.cz")
    User.find_or_create_by!(email: admin_email) do |u|
      u.name = "Admin"
      u.role = "admin"
      puts "  Created admin user: #{u.email}"
    end

    Visitor.update_all(status: "active")

    %w[Tomas Petr].each do |name|
      visitor = Visitor.find_or_initialize_by(name: name)
      if visitor.new_record?
        visitor.status = :active
        visitor.save!
        puts "  Created visitor: #{visitor.name}"
      elsif visitor.status.nil?
        visitor.update_column(:status, "active")
        puts "  Fixed visitor status: #{visitor.name}"
      end
    end

    puts "Setup complete. Property: #{property.name}, Meters: #{Meter.count}, Users: #{User.count}, Visitors: #{Visitor.count}"
  end
end
