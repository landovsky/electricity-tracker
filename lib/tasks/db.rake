namespace :db do
  desc "Download production SQLite database from K3s pod to tmp/db/"
  task :download do
    pod = `kubectl get pods -l app=sucha-meter -o jsonpath='{.items[0].metadata.name}'`.strip
    abort "No running sucha-meter pod found" if pod.empty?

    dir = Rails.root.join("tmp/db")
    FileUtils.mkdir_p(dir)
    dest = dir.join("production.sqlite3")
    snapshot = "/tmp/production-snapshot.sqlite3"

    # Production runs SQLite in WAL mode: copying the main file alone can miss committed
    # pages still in the -wal file. The online backup API produces a consistent single file.
    puts "Snapshotting #{pod}:/rails/storage/production.sqlite3 ..."
    system("kubectl", "exec", pod, "--", "sqlite3", "/rails/storage/production.sqlite3", ".backup '#{snapshot}'") ||
      abort("Snapshot failed")
    begin
      system("kubectl", "cp", "#{pod}:#{snapshot}", dest.to_s) || abort("Download failed")
    ensure
      system("kubectl", "exec", pod, "--", "rm", "-f", snapshot)
    end

    FileUtils.rm_f([ "#{dest}-wal", "#{dest}-shm" ])
    puts "Saved to #{dest} (#{File.size(dest)} bytes)"
  end

  desc "Load downloaded production database into local development environment"
  task :load do
    source = Rails.root.join("tmp/db/production.sqlite3")
    abort "#{source} not found — run `rake db:download` first" unless File.exist?(source)

    dev_db = Rails.root.join("storage/development.sqlite3").to_s
    sidecars = [ "#{dev_db}-wal", "#{dev_db}-shm" ]

    if File.exist?(dev_db)
      backup = "#{dev_db}.bak.#{Time.now.strftime('%Y%m%d%H%M%S')}"
      # .backup folds any un-checkpointed WAL data into the backup file
      system("sqlite3", dev_db, ".backup '#{backup}'") || abort("Backup of dev DB failed")
      puts "Backed up existing dev DB to #{backup}"
    end

    # A leftover -wal from the old dev DB would be replayed onto the new file and corrupt it
    FileUtils.rm_f(sidecars)
    FileUtils.cp(source, dev_db)
    puts "Copied production data to #{dev_db}"

    # Run migrations in case production is behind on schema
    system("bin/rails", "db:migrate") || abort("Migrations failed")
    puts "Done — local dev DB now has production data"
  end
end
