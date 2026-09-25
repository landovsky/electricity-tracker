# frozen_string_literal: true

require "rails_helper"

# 2025/26 the app was buggy and the family went back to the paper notebook. The settlement
# was reconciled by hand into a CSV log; this import replays it so the app can be used again.
RSpec.describe SettlementImport do
  include ActiveSupport::Testing::TimeHelpers

  let(:property) { create(:property) }
  let!(:vt) { create(:meter, :main_vt, property: property) }
  let!(:nt) { create(:meter, :main_nt, property: property) }
  let!(:garage) { create(:meter, :secondary, property: property, label: "Garáž") }
  let!(:jirka) { create(:visitor, property: property, name: "Jirka") }
  let!(:tereza) { create(:visitor, property: property, name: "Tereza") }
  let!(:email_named) { create(:visitor, property: property, name: "djakma@gmail.com") }
  let(:user) { create(:user) }
  let(:csv_path) { Rails.root.join("tmp/settlement_import_spec.csv").to_s }

  let(:csv) do
    <<~CSV
      at,visitor,action,vt,nt,garage,kwh,source,status,note
      2025-08-27 00:00,,reading,100,1000,50,,invoice,,start
      2025-09-19 10:00,Jirka,check_in,101,1003,50,,notebook,,
      2025-09-19 10:01,Tereza,check_in,101,1005,,,notebook,,
      2025-09-19 12:00,Tereza,manual_kwh,,,,5,notebook,,EV
      2025-09-21 10:00,Jirka,check_out,105,1042,67,,notebook,,
      2025-09-21 10:01,Tereza,check_out,105,1042,,,notebook,,
      2025-10-01 10:00,Marek,check_in,105,1043,,,app,,
      2025-10-02 10:00,Marek,check_out,106,1050,,,app,,
      2026-08-28 12:00,,reading,106,1051,67,,invoice,,end
      2026-09-19 10:00,Jirka,check_in,106,1052,67,,notebook,pending,still there?
    CSV
  end

  def import(apply: true, include_pending: false, created_before: nil)
    described_class.new(property: property, csv_path: csv_path, user: user,
                        meters: { vt: vt.label, nt: nt.label, garage: garage.label },
                        visitor_renames: { "Marek" => "djakma@gmail.com" },
                        include_pending: include_pending, apply: apply, created_before: created_before).call
  end

  before do
    File.write(csv_path, csv)
    allow($stdout).to receive(:puts)
  end

  after { FileUtils.rm_f(csv_path) }

  context "the app holds a buggy partial record of the same period (open stays, deleted check-outs)" do
    let!(:stale_stay) do
      event = MeterReadingEvent.create!(event_type: :check_in, recorded_at: Time.zone.parse("2025-09-19 09:00"),
                                        meter_readings: [ MeterReading.new(meter: vt, value_kwh: 101), MeterReading.new(meter: nt, value_kwh: 1003) ])
      Stay.create!(visitor: tereza, property: property, check_in_event: event)
    end
    let!(:stale_entry) do
      ManualConsumptionEntry.create!(visitor: tereza, property: property, date: Date.new(2025, 9, 19), kwh: 5, note: "nabíjení")
    end

    it "replaces it with the reconciled log so presence and meter deltas match the paper notebook" do
      expect(import).to eq(:applied)

      expect(stale_stay.reload).to be_discarded
      expect(stale_entry.reload).to be_discarded
      expect(Stay.live.open).to be_empty
      expect(Stay.live.count).to eq(3)
      expect(ManualConsumptionEntry.kept.sole.kwh).to eq(5)
    end

    it "keeps the discarded originals recoverable instead of hard-deleting them" do
      import
      expect(MeterReadingEvent.with_discarded.find(stale_stay.check_in_event_id)).to be_discarded
    end
  end

  context "a self-registered user's visitor was auto-named after their email" do
    it "renames it to the name the notebook uses so its stays attach to the right person" do
      import
      expect(email_named.reload.name).to eq("Marek")
      expect(email_named.stays.live.count).to eq(1)
    end
  end

  context "dry run is the default so a production run can be previewed safely" do
    it "validates every row through the services but writes nothing" do
      expect(import(apply: false)).to eq(:dry_run)
      expect(MeterReadingEvent.count).to eq(0)
      expect(email_named.reload.name).to eq("djakma@gmail.com")
    end
  end

  context "the import is re-run (e.g. after a deploy retry)" do
    it "recognises the window is already in the log's state and does not churn audits" do
      import
      expect { expect(import).to eq(:unchanged) }.not_to change(Audited::Audit, :count)
    end
  end

  context "the log is corrected after it was imported (e.g. a stay attributed to the wrong person)" do
    it "does not report 'already imported' but replays the corrected log" do
      import
      File.write(csv_path, csv.sub("2025-10-01 10:00,Marek", "2025-10-01 10:00,Tereza").sub("2025-10-02 10:00,Marek", "2025-10-02 10:00,Tereza"))
      expect(import).to eq(:applied)
      expect(tereza.stays.live.count).to eq(2)
    end
  end

  context "someone backdated a check-in into the window after the log was reconciled against the snapshot" do
    before do
      travel_to(Time.zone.parse("2026-09-25 12:00")) do
        CheckInVisitor.run!(visitor: tereza, property: property, recorded_by_user: user,
                            recorded_at: Time.zone.parse("2026-08-15 12:00"),
                            meter_readings: { vt.id.to_s => 106, nt.id.to_s => 1050 })
      end
    end

    it "refuses instead of silently discarding a stay the log doesn't know about" do
      expect { import(created_before: Time.zone.parse("2026-09-21")) }
        .to raise_error(SettlementImport::Refused, /Tereza.*created/m)
      expect(tereza.stays.live.open.count).to eq(1)
    end
  end

  context "someone is possibly still in the house after the billing period (pending row)" do
    it "leaves the pending check-in out until it is confirmed" do
      import
      expect(jirka.stays.live.open).to be_empty
    end

    it "opens the stay once confirmed with INCLUDE_PENDING" do
      import(include_pending: true)
      expect(jirka.stays.live.open.count).to eq(1)
    end
  end

  context "the family used the app again after the log was prepared" do
    before do
      MeterReadingEvent.create!(event_type: :periodic, recorded_at: Time.zone.parse("2026-10-01 10:00"),
                                meter_readings: [ MeterReading.new(meter: vt, value_kwh: 110), MeterReading.new(meter: nt, value_kwh: 1100) ])
    end

    it "refuses rather than discard real usage it doesn't know about" do
      expect { import }.to raise_error(SettlementImport::Refused, /after the log's last row/)
    end
  end

  context "a transcription error makes a meter go backwards" do
    let(:csv) do
      <<~CSV
        at,visitor,action,vt,nt,garage,kwh,source,status,note
        2025-09-19 10:00,Jirka,check_in,101,1003,50,,notebook,,
        2025-09-21 10:00,Jirka,check_out,105,1002,67,,notebook,,swapped digits
      CSV
    end

    it "fails on that row and rolls everything back" do
      expect { import }.to raise_error(SettlementImport::RowFailed, /line 3/)
      expect(MeterReadingEvent.count).to eq(0)
    end
  end
end
