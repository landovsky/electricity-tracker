# frozen_string_literal: true

# One-off migration to import electricity consumption data from XLS file.
#
# The XLS was created by transcribing physical paper records of visitor stays
# at the "Suchá" vacation house, covering Sep 2024 - Aug 2025.
#
# Approach: Boundary Events + ManualConsumptionEntry per visit
#
# Instead of creating per-visitor MeterReadings on stay events (which corrupt
# the period delta math due to synthetic check-in readings), we:
#
# 1. Create Stay records with check_in/check_out events that have NO meter readings.
#    These events are invisible to AnalyzePeriods (which joins on meter_readings).
#
# 2. Create exactly 2 "boundary" MeterReadingEvents with actual global VT+NT readings:
#    - Opening event: just before the first visit, actual meter state at that time
#    - Closing event: just after the last visit, actual meter state at that time
#    This defines a single period spanning the entire dataset.
#
# 3. Create one ManualConsumptionEntry per visit (kwh = vt_cons + nt_cons).
#    These are attributed directly to visitors in CalculateConsumption.
#
# With this structure:
#   total_kwh = VT_delta + NT_delta = 1941 kWh (actual meter delta)
#   sum(manual_entries) = 1941 kWh (XLS per-visitor totals)
#   shared_kwh = 0 → no unattributed consumption
#   per-visitor totals = their manual entries = correct XLS values
#
# Meter mapping (verified against XLS summary):
#   ~86xxx register (CEZ_N columns)  → VT (vysoký tarif) — small values, peak hours
#   ~122xxx register (CEZ_V columns) → NT (nízký tarif) — large values, off-peak
#
# Usage: bundle exec rails runner "XlsDataMigration.run"
class XlsDataMigration
  XLS_PATH = Rails.root.join("data/ELEKTRIKA-SUCHA-2025.xls")
  DATA_ROWS = (6..89) # XLS rows 6-89 (0-indexed) contain visit data

  # XLS column indices (0-indexed into our read_row array)
  # Jirka section
  COL_DATE       = 0
  COL_JIRKA_DAYS = 1
  COL_86K_JIRKA  = 2   # ~86xxx register reading (VT)
  COL_JIRKA_VT_C = 3   # Jirka VT consumption
  COL_122K_JIRKA = 4   # ~122xxx register reading (NT)
  COL_JIRKA_NT_C = 5   # Jirka NT consumption
  COL_SEC_A      = 7   # secondary meter reading (alt position)
  COL_SEC_B      = 8   # secondary meter reading (main position)
  COL_SEC_CONS   = 9   # secondary meter consumption

  # Petr section
  COL_PETR_DAYS  = 10  # days or sub-visitor marker (B/T/P)
  COL_86K_PETR   = 11  # ~86xxx register reading (VT)
  COL_PETR_VT_C  = 12  # Petr VT consumption
  COL_122K_PETR  = 13  # ~122xxx register reading (NT)
  COL_PETR_NT_C  = 14  # Petr NT consumption

  # Kristína section
  COL_KRIS_DAYS  = 15
  COL_86K_KRIS   = 16  # ~86xxx register reading (VT)
  COL_KRIS_VT_C  = 17  # Kristína VT consumption
  COL_122K_KRIS  = 18  # ~122xxx register reading (NT)
  COL_KRIS_NT_C  = 19  # Kristína NT consumption

  PETR_SUB_VISITORS = { "B" => "Bára", "T" => "Landovští", "P" => "Petr" }.freeze

  def self.run
    new.run
  end

  def run
    puts "=" * 60
    puts "XLS Data Migration: #{XLS_PATH}"
    puts "=" * 60

    clear_database!

    ActiveRecord::Base.transaction do
      setup_property_and_meters!
      create_visitors!
      create_admin_user!
      visits = parse_xls!
      create_records!(visits)
      verify!
    end

    puts "\n#{'=' * 60}"
    puts "Migration complete!"
    puts "=" * 60
  end

  private

  def clear_database!
    puts "\nClearing database..."
    conn = ActiveRecord::Base.connection
    conn.execute("PRAGMA foreign_keys = OFF")
    %w[audits meter_readings stays meter_reading_events manual_consumption_entries
       meters visitors properties].each do |table|
      conn.execute("DELETE FROM #{table}")
    end
    # Preserve admin users, delete the rest
    conn.execute("DELETE FROM users WHERE role != 'admin'")
    conn.execute("PRAGMA foreign_keys = ON")
    puts "  Done."
  end

  def setup_property_and_meters!
    puts "\nCreating property and meters..."
    @property = Property.create!(name: "Suchá")

    @meter_vt = Meter.create!(
      property: @property,
      label: "Hlavní - VT",
      meter_type: "main",
      meter_group: "main",
      unit: "kWh"
    )

    @meter_nt = Meter.create!(
      property: @property,
      label: "Hlavní - NT",
      meter_type: "main",
      meter_group: "main",
      unit: "kWh"
    )

    @meter_sec = Meter.create!(
      property: @property,
      label: "Elektroměr garáž",
      meter_type: "secondary",
      unit: "kWh"
    )

    puts "  Property: #{@property.name}"
    puts "  Meters: #{@meter_vt.label} (86xxx), #{@meter_nt.label} (122xxx), #{@meter_sec.label}"
  end

  def create_visitors!
    puts "\nCreating visitors..."
    @visitors = {}
    %w[Jirka Petr Kristína Landovští Bára].each do |name|
      @visitors[name] = Visitor.create!(name: name, status: "active")
      puts "  #{name}"
    end
  end

  def create_admin_user!
    @admin = User.find_by(role: "admin") || User.create!(
      name: "Migration",
      email: "migration@sucha.local",
      role: "admin"
    )
  end

  def parse_xls!
    puts "\nParsing XLS..."
    require "roo"
    require "roo-xls"

    workbook = Roo::Excel.new(XLS_PATH.to_s)
    @sheet = workbook.sheet(0)

    # Initialize opening reading accumulators (captured from first check-in rows)
    @opening_vt = nil
    @opening_nt = nil

    visits = []
    visits.concat(parse_jirka_visits)
    visits.concat(parse_petr_visits)
    visits.concat(parse_kristina_visits)

    visits.sort_by! { |v| v[:check_in_date] }

    puts "  Parsed #{visits.size} visits total"
    visits.each do |v|
      d_vt = v[:vt_cons] || "?"
      d_nt = v[:nt_cons] || "?"
      puts "    %-10s %s → %s (%dd) VT=%s NT=%s" % [
        v[:visitor], v[:check_in_date], v[:check_out_date], v[:days], d_vt, d_nt
      ]
    end

    puts "  Opening readings: VT=#{@opening_vt&.to_i} NT=#{@opening_nt&.to_i}"
    visits
  end

  # Parse Jirka visits from check-out rows, computing check-in from consumption.
  def parse_jirka_visits
    visits = []
    pending_checkin_date = nil

    DATA_ROWS.each do |row_idx|
      row = read_row(row_idx)
      date = parse_date(row_idx, COL_DATE)

      vt_reading = numeric_val(row[COL_86K_JIRKA])   # check-out VT reading
      nt_reading = numeric_val(row[COL_122K_JIRKA])   # check-out NT reading
      days = numeric_val(row[COL_JIRKA_DAYS])
      vt_cons = numeric_val(row[COL_JIRKA_VT_C])      # VT consumption
      nt_cons = numeric_val(row[COL_JIRKA_NT_C])      # NT consumption
      sec_out = secondary_reading(row)
      sec_cons = numeric_val(row[COL_SEC_CONS])

      # Track check-in dates (rows with readings but no days)
      if (vt_reading || nt_reading) && (!days || days == 0)
        # Capture opening readings from the very first check-in row
        @opening_vt ||= vt_reading if vt_reading
        @opening_nt ||= nt_reading if nt_reading
        pending_checkin_date = date if date
        next
      end

      # Check-out row: has days count
      next unless days && days > 0 && (vt_reading || nt_reading)
      next unless pending_checkin_date

      vt_cons ||= 0
      nt_cons ||= 0
      sec_cons ||= 0

      visits << {
        visitor: "Jirka",
        check_in_date: pending_checkin_date,
        check_out_date: date || (pending_checkin_date + days.to_i),
        days: days.to_i,
        vt_in: vt_reading ? vt_reading - vt_cons : nil,
        vt_out: vt_reading,
        vt_cons: vt_cons,
        nt_in: nt_reading ? nt_reading - nt_cons : nil,
        nt_out: nt_reading,
        nt_cons: nt_cons,
        sec_in: sec_out ? sec_out - sec_cons : nil,
        sec_out: sec_out
      }
      pending_checkin_date = nil
    end

    # Handle Jirka's last visit (rows 85-89) where secondary is on a separate row
    fix_jirka_last_visit_secondary(visits)

    # Capture secondary-only readings that appear on non-Jirka checkout rows
    # (e.g., garage meter readings during Landovští visits at rows 42-43, 80-82)
    capture_orphaned_secondary(visits)

    puts "  Jirka: #{visits.size} visits"
    visits
  end

  # Row 89 has secondary meter data for the last Jirka visit (split from row 88)
  def fix_jirka_last_visit_secondary(visits)
    return if visits.empty?

    last = visits.last
    return unless last[:check_out_date] == Date.new(2025, 8, 24) && last[:sec_out].nil?

    row89 = read_row(89)
    sec_out = secondary_reading(row89)
    sec_cons = numeric_val(row89[COL_SEC_CONS])
    if sec_out && sec_cons
      last[:sec_out] = sec_out
      last[:sec_in] = sec_out - sec_cons
    end
  end

  # The secondary (garage) meter is tracked in the Jirka columns (7-9) but
  # sometimes appears on rows where Jirka has no main meter data (no days in col 1).
  # These are periods when someone else visited and used the garage.
  # We collect these as separate Jirka secondary-only visits.
  def capture_orphaned_secondary(visits)
    # Collect all secondary check-out rows already captured
    captured_sec_outs = visits.select { |v| v[:sec_out] }.map { |v| v[:sec_out] }.to_set

    pending_sec_checkin = nil

    DATA_ROWS.each do |row_idx|
      row = read_row(row_idx)
      date = parse_date(row_idx, COL_DATE)
      sec = secondary_reading(row)
      sec_cons = numeric_val(row[COL_SEC_CONS])

      next unless sec

      if sec_cons && sec_cons > 0
        # Check-out row for secondary
        next if captured_sec_outs.include?(sec) # Already captured in a main visit

        checkin_date = pending_sec_checkin&.[](:date) || date
        next unless checkin_date

        visits << {
          visitor: "Jirka",
          check_in_date: checkin_date,
          check_out_date: date || checkin_date,
          days: 0, # secondary-only, no actual stay days
          vt_in: nil, vt_out: nil, vt_cons: 0,
          nt_in: nil, nt_out: nil, nt_cons: 0,
          sec_in: sec - sec_cons,
          sec_out: sec
        }
        pending_sec_checkin = nil
      else
        # Check-in row for secondary
        pending_sec_checkin = { date: date, reading: sec } if date
      end
    end
  end

  def parse_petr_visits
    visits = []
    pending_checkin = nil
    last_date = nil

    DATA_ROWS.each do |row_idx|
      row = read_row(row_idx)
      date = parse_date(row_idx, COL_DATE)
      last_date = date if date

      marker = row[COL_PETR_DAYS]
      vt_reading = numeric_val(row[COL_86K_PETR])
      nt_reading = numeric_val(row[COL_122K_PETR])

      next unless vt_reading || nt_reading

      if marker.is_a?(String) && PETR_SUB_VISITORS.key?(marker.strip)
        # Check-in row with sub-visitor marker
        pending_checkin = {
          visitor: PETR_SUB_VISITORS[marker.strip],
          date: date || last_date
        }
      elsif (days = numeric_val(marker)) && days > 0
        # Check-out row
        next unless pending_checkin

        vt_cons = numeric_val(row[COL_PETR_VT_C]) || 0
        nt_cons = numeric_val(row[COL_PETR_NT_C]) || 0

        check_out_date = date || last_date || (pending_checkin[:date] + days.to_i)
        check_in_date = pending_checkin[:date] || (check_out_date - days.to_i)

        visits << {
          visitor: pending_checkin[:visitor],
          check_in_date: check_in_date,
          check_out_date: check_out_date,
          days: days.to_i,
          vt_in: vt_reading ? vt_reading - vt_cons : nil,
          vt_out: vt_reading,
          vt_cons: vt_cons,
          nt_in: nt_reading ? nt_reading - nt_cons : nil,
          nt_out: nt_reading,
          nt_cons: nt_cons,
          sec_in: nil,
          sec_out: nil
        }
        pending_checkin = nil
      end
    end

    puts "  Petr section: #{visits.size} visits (#{visits.map { |v| v[:visitor] }.tally})"
    visits
  end

  def parse_kristina_visits
    visits = []
    pending_checkin_date = nil
    last_date = nil

    DATA_ROWS.each do |row_idx|
      row = read_row(row_idx)
      date = parse_date(row_idx, COL_DATE)
      last_date = date if date

      vt_reading = numeric_val(row[COL_86K_KRIS])
      nt_reading = numeric_val(row[COL_122K_KRIS])
      days = numeric_val(row[COL_KRIS_DAYS])
      vt_cons = numeric_val(row[COL_KRIS_VT_C])
      nt_cons = numeric_val(row[COL_KRIS_NT_C])

      next unless vt_reading || nt_reading

      if days && days > 0
        # Check-out row
        next unless pending_checkin_date

        vt_cons ||= 0
        nt_cons ||= 0

        check_out_date = date || last_date || (pending_checkin_date + days.to_i)

        visits << {
          visitor: "Kristína",
          check_in_date: pending_checkin_date,
          check_out_date: check_out_date,
          days: days.to_i,
          vt_in: vt_reading ? vt_reading - vt_cons : nil,
          vt_out: vt_reading,
          vt_cons: vt_cons,
          nt_in: nt_reading ? nt_reading - nt_cons : nil,
          nt_out: nt_reading,
          nt_cons: nt_cons,
          sec_in: nil,
          sec_out: nil
        }
        pending_checkin_date = nil
      else
        # Check-in row
        pending_checkin_date = date || last_date
      end
    end

    puts "  Kristína: #{visits.size} visits"
    visits
  end

  # Main orchestrator: creates stays, boundary events, and manual entries.
  # Stays have NO meter readings — their events are invisible to AnalyzePeriods,
  # which only fetches events joined on meter_readings. Two boundary events with
  # actual global VT+NT readings define one period spanning the full dataset.
  # ManualConsumptionEntry records carry per-visitor kWh attribution directly.
  def create_records!(visits)
    puts "\nCreating DB records..."

    create_stay_records!(visits)
    create_boundary_events!(visits)
    create_manual_entries!(visits)

    puts "  Created #{Stay.count} stays, #{MeterReadingEvent.count} events total, " \
         "#{MeterReading.count} readings, #{ManualConsumptionEntry.count} manual entries"
  end

  # Creates Stay records with check_in/check_out events that have NO meter readings.
  # These events will not appear in AnalyzePeriods.fetch_meter_reading_events since
  # that query joins on meter_readings. Stays serve the dashboard and visit history.
  def create_stay_records!(visits)
    visits.each do |visit|
      visitor = @visitors.fetch(visit[:visitor])

      check_in_event = MeterReadingEvent.new(
        event_type: "check_in",
        recorded_at: visit[:check_in_date].to_time,
        recorded_by_user: @admin
      )
      check_in_event.save!(validate: false)

      check_out_event = MeterReadingEvent.new(
        event_type: "check_out",
        recorded_at: visit[:check_out_date].to_time,
        recorded_by_user: @admin
      )
      check_out_event.save!(validate: false)

      Stay.new(
        visitor: visitor,
        property: @property,
        check_in_event: check_in_event,
        check_out_event: check_out_event
      ).save!(validate: false)
    end

    puts "  Stay records: #{Stay.count} stays created"
  end

  # Creates exactly 2 boundary MeterReadingEvents with actual global VT+NT readings.
  # These are the ONLY events with meter readings and define the single reporting period.
  #
  # Opening event: 1 minute before the first visit's check-in
  # Closing event: 1 day after the last visit's check-out (ensures last-day manual entries
  #               are included in find_manual_entries which uses: date < period_end.to_date)
  #
  # Opening VT/NT: captured from the XLS first check-in row (@opening_vt / @opening_nt)
  # Closing VT/NT: from the chronologically last checkout with both vt_out and nt_out
  def create_boundary_events!(visits)
    # Determine first and last visit dates
    first_visit = visits.min_by { |v| v[:check_in_date] }
    last_visit = visits.max_by { |v| v[:check_out_date] }

    return unless first_visit && last_visit

    # Closing readings: last chronological checkout with both VT and NT readings
    # All three visitor sections track the same physical meters, so the last checkout
    # across all sections gives the final global meter state.
    closing_visit = visits.select { |v| v[:vt_out] && v[:nt_out] }.max_by { |v| v[:check_out_date] }
    closing_vt = closing_visit&.dig(:vt_out)
    closing_nt = closing_visit&.dig(:nt_out)

    # Opening readings: derived from closing minus total per-visitor consumption.
    # This ensures boundary delta exactly equals sum of ManualConsumptionEntry records,
    # avoiding the sanity-check mismatch. The XLS check-in row readings don't perfectly
    # reconcile with per-visitor consumption totals (6 kWh gap due to rounding/gaps).
    total_vt_cons = visits.sum { |v| v[:vt_cons] || 0 }
    total_nt_cons = visits.sum { |v| v[:nt_cons] || 0 }
    opening_vt = closing_vt - total_vt_cons if closing_vt
    opening_nt = closing_nt - total_nt_cons if closing_nt

    unless opening_vt && opening_nt && closing_vt && closing_nt
      puts "  WARNING: Missing opening or closing readings — boundary events not created!"
      return
    end

    # Opening boundary event: 1 minute before the first check-in
    # This ensures no stay's check_in_event.recorded_at <= open_event.recorded_at
    # (required so find_present_visitors returns [] for the single period)
    open_recorded_at = first_visit[:check_in_date].to_time - 1.minute
    open_event = MeterReadingEvent.new(
      event_type: "check_in",
      recorded_at: open_recorded_at,
      recorded_by_user: @admin
    )
    open_event.save!(validate: false)
    create_reading!(open_event, @meter_vt, opening_vt)
    create_reading!(open_event, @meter_nt, opening_nt)

    # Closing boundary event: 1 day after the last checkout
    # Using +1.day (not +1.minute) so that manual entries dated on the last checkout date
    # satisfy: date < close_event.recorded_at.to_date (used in find_manual_entries)
    close_recorded_at = last_visit[:check_out_date].to_time + 1.day
    close_event = MeterReadingEvent.new(
      event_type: "check_out",
      recorded_at: close_recorded_at,
      recorded_by_user: @admin
    )
    close_event.save!(validate: false)
    create_reading!(close_event, @meter_vt, closing_vt)
    create_reading!(close_event, @meter_nt, closing_nt)

    # Year-boundary events: create intermediate boundary events at each Jan 1 so that
    # year-filtered reports (e.g. ?year=2025) find events within their date range.
    # Readings are computed by accumulating per-visit consumption chronologically.
    create_year_boundary_events!(visits, opening_vt, opening_nt)

    vt_delta = closing_vt - opening_vt
    nt_delta = closing_nt - opening_nt
    total_delta = vt_delta + nt_delta

    puts "  Boundary events:"
    puts "    Open:  #{open_event.recorded_at.to_date} — VT=#{opening_vt.to_i} NT=#{opening_nt.to_i}"
    puts "    Close: #{close_event.recorded_at.to_date} — VT=#{closing_vt.to_i} NT=#{closing_nt.to_i}"
    puts "    Deltas: VT=#{vt_delta.to_i} (expected 269), NT=#{nt_delta.to_i} (expected 1672)"
    puts "    Total: #{total_delta.to_i} kWh (expected 1941)"
  end

  # Creates intermediate boundary events at each Jan 1 that falls between the opening
  # and closing dates. This allows year-filtered reports (?year=2025) to find boundary
  # events within their date range and build periods correctly.
  #
  # Readings are computed by accumulating per-visit VT/NT consumption chronologically
  # from the opening readings, so each year boundary has the correct global meter state.
  def create_year_boundary_events!(visits, opening_vt, opening_nt)
    first_year = visits.min_by { |v| v[:check_in_date] }[:check_in_date].year
    last_year = visits.max_by { |v| v[:check_out_date] }[:check_out_date].year

    return if first_year == last_year # No year crossings

    # Accumulate consumption chronologically to compute meter state at each Jan 1
    sorted_visits = visits.sort_by { |v| v[:check_out_date] }

    (first_year + 1..last_year).each do |year|
      jan1 = Date.new(year, 1, 1)

      # Sum consumption from all visits with check_out_date before Jan 1
      vt_before = sorted_visits.select { |v| v[:check_out_date] < jan1 }.sum { |v| v[:vt_cons] || 0 }
      nt_before = sorted_visits.select { |v| v[:check_out_date] < jan1 }.sum { |v| v[:nt_cons] || 0 }

      mid_vt = opening_vt + vt_before
      mid_nt = opening_nt + nt_before

      # Create TWO events: one at end of old year, one at start of new year.
      # AnalyzePeriods filters by date_range, so each year needs both a start and end
      # event within its range. Identical readings ensure zero delta between them.
      dec31 = Date.new(year - 1, 12, 31)
      [ dec31.end_of_day, jan1.beginning_of_day ].each do |timestamp|
        event = MeterReadingEvent.new(
          event_type: "check_out",
          recorded_at: timestamp,
          recorded_by_user: @admin
        )
        event.save!(validate: false)
        create_reading!(event, @meter_vt, mid_vt)
        create_reading!(event, @meter_nt, mid_nt)
      end

      puts "    Year boundary #{year}: VT=#{mid_vt.to_i} NT=#{mid_nt.to_i}"
    end
  end

  # Creates one ManualConsumptionEntry per visit for per-visitor kWh attribution.
  # Skips visits with zero total consumption (secondary-only records with no VT/NT).
  # kwh = vt_cons + nt_cons (raw XLS consumption values stored in visit hash)
  def create_manual_entries!(visits)
    count = 0

    visits.each do |visit|
      visitor = @visitors.fetch(visit[:visitor])
      vt_cons = visit[:vt_cons] || 0
      nt_cons = visit[:nt_cons] || 0
      total_kwh = vt_cons + nt_cons

      next if total_kwh <= 0

      ManualConsumptionEntry.new(
        visitor: visitor,
        property: @property,
        date: visit[:check_out_date],
        kwh: total_kwh,
        note: "XLS import: #{visit[:days]}d (#{visit[:check_in_date]} – #{visit[:check_out_date]}), " \
              "VT=#{vt_cons.to_i} NT=#{nt_cons.to_i}",
        recorded_by_user: @admin
      ).save!(validate: false)

      count += 1
    end

    puts "  Manual entries: #{count} created"
  end

  def create_reading!(event, meter, value)
    reading = MeterReading.new(
      meter_reading_event: event,
      meter: meter,
      value_kwh: value
    )
    reading.save!(validate: false)
  end

  def verify!
    puts "\n#{'=' * 60}"
    puts "VERIFICATION"
    puts "=" * 60

    puts "\nRecord counts:"
    puts "  Properties: #{Property.count}"
    puts "  Meters: #{Meter.count}"
    puts "  Visitors: #{Visitor.count}"
    puts "  Users: #{User.count}"
    puts "  Stays: #{Stay.count}"
    puts "  MeterReadingEvents: #{MeterReadingEvent.count}"
    puts "  MeterReadings: #{MeterReading.count}"
    puts "  ManualConsumptionEntries: #{ManualConsumptionEntry.count}"

    puts "\nPer-visitor consumption (from ManualConsumptionEntries):"
    puts "  Expected from XLS summary:"
    puts "    Jirka:     802 kWh"
    puts "    Bára:      242 kWh"
    puts "    Landovští: 464 kWh"
    puts "    Petr:      137 kWh"
    puts "    Kristína:  296 kWh"
    puts "    GRAND:     1941 kWh"
    puts ""
    puts "  Computed from ManualConsumptionEntries:"

    expected = {
      "Bára"      => 242,
      "Jirka"     => 802,
      "Kristína"  => 296,
      "Landovští" => 464,
      "Petr"      => 137
    }

    grand_total = BigDecimal("0")

    Visitor.order(:name).each do |visitor|
      total = visitor.manual_consumption_entries.sum(:kwh)
      grand_total += total
      exp = expected[visitor.name]
      status = if exp
        total.to_i == exp ? " OK" : " MISMATCH (expected #{exp})"
      else
        ""
      end
      puts "    %-12s %s kWh%s" % [ "#{visitor.name}:", total.to_i, status ]
    end

    grand_ok = grand_total.to_i == 1941
    puts "    %-12s %s kWh%s" % [ "GRAND:", grand_total.to_i, grand_ok ? " OK" : " MISMATCH (expected 1941)" ]

    # Boundary event check
    events_with_readings = MeterReadingEvent.joins(:meter_readings).distinct.count
    puts "\n  Events with readings: #{events_with_readings}"
  end

  # === Helper methods ===

  def read_row(row_idx)
    (1..20).map { |col| @sheet.cell(row_idx + 1, col) } # roo is 1-indexed
  end

  def parse_date(row_idx, col_idx)
    val = @sheet.cell(row_idx + 1, col_idx + 1)
    return nil if val.nil? || val == ""
    return val.to_date if val.is_a?(Date) || val.is_a?(DateTime) || val.is_a?(Time)
    nil
  end

  def numeric_val(val)
    return nil if val.nil? || val == ""
    return nil if val.is_a?(String) && !val.match?(/\A[\d.]/)
    f = val.to_f
    f == 0.0 ? nil : f
  end

  def secondary_reading(row)
    numeric_val(row[COL_SEC_A]) || numeric_val(row[COL_SEC_B])
  end
end
