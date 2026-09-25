# frozen_string_literal: true

require "csv"

# Loads a hand-reconciled settlement event log (e.g. data/vyuctovani-2026/events.csv) into
# the app, so the family can resume check-ins after a period that was tracked on paper.
#
# The CSV is canonical for its time window. Everything the app holds inside that window
# (events, their readings, the stays anchored to them, manual entries) is soft-discarded
# and the log is replayed through the regular
# services: CheckInVisitor / CheckOutVisitor / CreateManualConsumptionEntry, plus
# `periodic` reading events for rows without a visitor. The services' own C1/C2/C6
# validations run on every row, so a bad log fails loudly instead of corrupting periods.
#
# Safety:
# - Dry run by default: the whole import runs in a transaction that is rolled back.
# - Refuses when the app holds live events or manual entries AFTER the log's last row, or
#   anything inside the window created after `created_before` (the data the log was
#   reconciled against), so real usage since then is never silently discarded.
# - Every discarded row is listed by id; audits are attributed to the importing user.
#   Undo = restore a DB backup taken right before APPLY (see data/vyuctovani-2026/README.md).
# - Idempotent: a second apply finds the window already matching the log and does nothing.
#
# CSV columns: at (Europe/Prague "YYYY-MM-DD HH:MM"), visitor, action (check_in |
# check_out | manual_kwh | reading), vt, nt, garage, kwh, source, status, note.
# Rows with status "pending" are skipped unless include_pending is set.
class SettlementImport
  class Refused < StandardError; end
  class RowFailed < StandardError; end

  NOTE_PREFIX = "import vyúčtování"

  Row = Struct.new(:line, :at, :visitor, :action, :vt, :nt, :garage, :kwh, :source, :note, keyword_init: true)

  attr_reader :log, :rows, :window_start, :window_end

  # meters: { vt: label, nt: label, garage: label }
  # visitor_renames: { "new name" => "current name" } applied before replay (e.g. "Marek" => "djakma@gmail.com")
  # created_before: refuse if any in-window row was created after this time (nil = no check)
  def initialize(property:, csv_path:, user:, meters:, visitor_renames: {}, include_pending: false, apply: false,
                 created_before: nil)
    @property = property
    @created_before = created_before
    @user = user
    @apply = apply
    @visitor_renames = visitor_renames
    @meters = meters.transform_values { |label| property.meters.kept.find_by!(label: label) }
    @rows = parse(csv_path, include_pending)
    @window_start = @rows.first.at
    @window_end = @rows.last.at
    @log = []
  end

  def call
    guard_no_later_events!
    if already_imported?
      say "Already imported: live data in #{window_label} matches the log (#{rows.size} rows). Nothing to do."
      return :unchanged
    end

    guard_nothing_newer_in_window!

    Audited.audit_class.as_user(@user) do
      ActiveRecord::Base.transaction do
        rename_visitors!
        discard_window!
        replay!
        say(@apply ? "APPLIED." : "DRY RUN — rolled back. Re-run with APPLY=1 to write.")
        raise ActiveRecord::Rollback unless @apply
      end
    end
    @apply ? :applied : :dry_run
  end

  private

  def parse(path, include_pending)
    CSV.read(path, headers: true, encoding: "bom|utf-8").each_with_index.filter_map do |r, i|
      next if r["status"] == "pending" && !include_pending

      Row.new(line: i + 2, at: Time.zone.parse(r["at"]) || raise(ArgumentError, "line #{i + 2}: bad time #{r['at']}"),
              visitor: r["visitor"].presence, action: r["action"], vt: dec(r["vt"]), nt: dec(r["nt"]),
              garage: dec(r["garage"]), kwh: dec(r["kwh"]), source: r["source"], note: r["note"])
    end.tap do |rows|
      raise ArgumentError, "empty log" if rows.empty?

      rows.each_cons(2) do |a, b|
        raise ArgumentError, "line #{b.line}: not chronological (#{b.at} after #{a.at})" if b.at <= a.at
      end
    end
  end

  def dec(value) = value.present? ? BigDecimal(value) : nil

  def window_label = "#{I18n.l(window_start)} – #{I18n.l(window_end)}"

  def say(message)
    @log << message
    puts message
  end

  def property_events = MeterReadingEvent.where(id: MeterReading.joins(:meter).where(meters: { property_id: @property.id }).select(:meter_reading_event_id))

  def guard_no_later_events!
    later = property_events.kept.where("recorded_at > ?", window_end)
    if later.exists?
      raise Refused, "#{later.count} live event(s) after the log's last row (#{I18n.l(window_end)}), " \
                     "first at #{I18n.l(later.minimum(:recorded_at))}. Add them to the log or narrow it."
    end

    later_entries = ManualConsumptionEntry.kept.where(property: @property).where("date > ?", window_end.to_date)
    return unless later_entries.exists?

    raise Refused, "#{later_entries.count} manual entr(y/ies) dated after the log's last row: " \
                   "#{later_entries.map { |e| "##{e.id} #{e.date}" }.join(', ')}"
  end

  # Rows the log was not reconciled against (created after the snapshot, or a stay that
  # straddles the window start) would be lost by the discard — refuse instead.
  def guard_nothing_newer_in_window!
    events, stays, entries = window_targets
    problems = []
    straddling = stays.select { |s| s.check_in_event && s.check_in_event.recorded_at < window_start }
    problems += straddling.map { |s| "stay ##{s.id} (#{s.visitor.name}) checked in before the window" }
    if @created_before
      newer = (events + stays + entries).select { |r| r.created_at > @created_before && !imported?(r) }
      problems += newer.map { |r| "#{describe(r)} created #{I18n.l(r.created_at)}" }
    end
    return if problems.empty?

    raise Refused, "in-window data the log doesn't cover:\n  " + problems.join("\n  ")
  end

  def imported?(record) = record.note.to_s.start_with?(NOTE_PREFIX)

  def window_targets
    events = property_events.where(recorded_at: window_start..window_end)
    stays = Stay.kept.where(property: @property)
                .where("check_in_event_id IN (:ids) OR check_out_event_id IN (:ids)", ids: events.select(:id))
                .includes(:visitor, :check_in_event).to_a
    entries = ManualConsumptionEntry.kept.where(property: @property, date: window_start.to_date..window_end.to_date)
                                    .includes(:visitor).to_a
    [ events.kept.order(:recorded_at).to_a, stays, entries ]
  end

  def describe(record)
    case record
    when MeterReadingEvent then "event ##{record.id} #{record.event_type} #{I18n.l(record.recorded_at)}#{" (#{record.visitor.name})" if record.visitor}"
    when Stay then "stay ##{record.id} #{record.visitor.name} (#{record.status})"
    when ManualConsumptionEntry then "manual entry ##{record.id} #{record.visitor.name} #{record.date} #{record.kwh} kWh"
    end
  end

  # The window is already in the log's state when every live event/entry in it came from
  # this import and the (time, type, readings) sequence equals the log.
  def already_imported?
    live_events = property_events.kept.where(recorded_at: window_start..window_end).order(:recorded_at).includes(meter_readings: :meter)
    live_entries = ManualConsumptionEntry.kept.where(property: @property, date: window_start.to_date..window_end.to_date)
    return false unless (live_events + live_entries.to_a).all? { |r| r.note.to_s.start_with?(NOTE_PREFIX) }

    event_rows = rows.reject { |r| r.action == "manual_kwh" }
    return false unless event_rows.size == live_events.size

    events_match = event_rows.zip(live_events).all? do |row, e|
      vals = e.meter_readings.select(&:kept?).to_h { |mr| [ mr.meter_id, mr.value_kwh ] }
      [ row.at.to_i, row.action == "reading" ? "periodic" : row.action, row.vt, row.nt, row.visitor ] ==
        [ e.recorded_at.to_i, e.event_type, vals[@meters[:vt].id], vals[@meters[:nt].id], e.visitor&.name ] &&
        (row.garage.nil? || row.garage == vals[@meters[:garage].id])
    end
    expected_entries = rows.select { |r| r.action == "manual_kwh" }.map { |r| [ r.visitor, r.at.to_date, r.kwh ] }.sort
    actual_entries = live_entries.map { |e| [ e.visitor.name, e.date, e.kwh ] }.sort
    events_match && expected_entries == actual_entries
  end

  def rename_visitors!
    @visitor_renames.each do |new_name, old_name|
      next if @property.visitors.kept.exists?(name: new_name)

      visitor = @property.visitors.kept.find_by!(name: old_name)
      visitor.update!(name: new_name)
      say "Renamed visitor ##{visitor.id} '#{old_name}' → '#{new_name}'"
    end
  end

  def discard_window!
    events, stays, entries = window_targets
    say "Discarding in #{window_label}: #{events.size} events, #{stays.size} stays, #{entries.size} manual entries"
    (stays + entries + events).each { |r| say "  - #{describe(r)}" }
    stays.each(&:discard!)
    entries.each(&:discard!)
    events.each do |event|
      readings = event.meter_readings.kept.to_a
      say "    readings #{readings.map(&:id).join(',')}" if readings.any?
      readings.each(&:discard!)
      event.discard!
    end
  end

  def replay!
    rows.each do |row|
      outcome = run_row(row)
      next if outcome == :ok

      raise RowFailed, "line #{row.line} (#{row.at.strftime('%-d.%-m.%Y %H:%M')} #{row.visitor} #{row.action}): " \
                       "#{outcome.errors.full_messages.to_sentence}"
    end
    say "Replayed #{rows.size} rows (#{rows.count { |r| r.action == 'check_in' }} check-ins, " \
        "#{rows.count { |r| r.action == 'check_out' }} check-outs, #{rows.count { |r| r.action == 'manual_kwh' }} manual entries, " \
        "#{rows.count { |r| r.action == 'reading' }} readings)"
  end

  def run_row(row)
    note = [ NOTE_PREFIX, "[#{row.source}]", row.note ].compact_blank.join(" ")
    case row.action
    when "check_in"
      ok CheckInVisitor.run(visitor: visitor(row), property: @property, recorded_by_user: @user,
                            recorded_at: row.at, meter_readings: readings(row), note: note)
    when "check_out"
      ok CheckOutVisitor.run(visitor: visitor(row), property: @property, recorded_by_user: @user,
                             recorded_at: row.at, meter_readings: readings(row), note: note)
    when "manual_kwh"
      ok CreateManualConsumptionEntry.run(visitor: visitor(row), property: @property, recorded_by_user: @user,
                                          date: row.at.to_date, kwh: row.kwh.to_f, note: note)
    when "reading"
      create_reading_event!(row, note)
    else
      raise ArgumentError, "line #{row.line}: unknown action #{row.action.inspect}"
    end
  end

  def ok(outcome) = outcome.valid? ? :ok : outcome

  def visitor(row)
    @property.visitors.kept.find_by(name: row.visitor) ||
      raise(RowFailed, "line #{row.line}: no visitor named #{row.visitor.inspect} on #{@property.name}")
  end

  def readings(row)
    { @meters[:vt].id.to_s => row.vt, @meters[:nt].id.to_s => row.nt, @meters[:garage].id.to_s => row.garage }.compact
  end

  # Visitors-mode has no service for a bare reading (RecordMeterReading is meter_only);
  # model validations (C1 monotonic, C4 main reading) still apply.
  def create_reading_event!(row, note)
    event = MeterReadingEvent.new(event_type: :periodic, recorded_at: row.at, recorded_by_user: @user, note: note)
    readings(row).each { |meter_id, value| event.meter_readings.build(meter_id: meter_id.to_i, value_kwh: value) }
    event.save!
    :ok
  rescue ActiveRecord::RecordInvalid => e
    raise RowFailed, "line #{row.line} (#{row.at.strftime('%-d.%-m.%Y %H:%M')} reading): #{e.record.errors.full_messages.to_sentence}"
  end
end
