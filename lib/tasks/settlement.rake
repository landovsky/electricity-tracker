namespace :settlement do
  desc "Replay a hand-reconciled settlement log into the app (dry run unless APPLY=1). " \
       "Env: CSV (default data/vyuctovani-2026/events.csv), PROPERTY (subdomain, default sepot), " \
       "USER_EMAIL (recorded_by, default first admin), CREATED_BEFORE (refuse in-window rows created later; " \
       "default 2026-09-21 = snapshot the log was reconciled against, 'none' to skip), INCLUDE_PENDING=1, APPLY=1"
  task import: :environment do
    property = Property.kept.find_by!(subdomain: ENV.fetch("PROPERTY", "sepot"))
    user = ENV["USER_EMAIL"].present? ? User.find_by!(email: ENV["USER_EMAIL"]) : User.where(role: "admin").order(:id).first!
    csv = ENV.fetch("CSV", Rails.root.join("data/vyuctovani-2026/events.csv").to_s)
    cutoff = ENV.fetch("CREATED_BEFORE", "2026-09-21")
    created_before = cutoff == "none" ? nil : Time.zone.parse(cutoff) || abort("bad CREATED_BEFORE #{cutoff}")

    puts "Settlement import: #{csv} → #{property.name} (as #{user.email})"
    SettlementImport.new(
      property: property,
      csv_path: csv,
      user: user,
      meters: { vt: "Hlavní - VT", nt: "Hlavní - NT", garage: "Elektroměr garáž" },
      visitor_renames: { "Marek" => "djakma@gmail.com" },
      include_pending: ENV["INCLUDE_PENDING"] == "1",
      apply: ENV["APPLY"] == "1",
      created_before: created_before
    ).call
  rescue SettlementImport::Refused, SettlementImport::RowFailed, ArgumentError, ActiveRecord::RecordNotFound => e
    abort "ABORTED (nothing written): #{e.message}"
  end
end
