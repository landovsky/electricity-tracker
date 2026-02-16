class CreateMeterReadingEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :meter_reading_events do |t|
      t.datetime :recorded_at, null: false
      t.bigint :recorded_by_user_id
      t.string :event_type, null: false
      t.text :note
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :meter_reading_events, :deleted_at
    add_index :meter_reading_events, :recorded_by_user_id
    add_index :meter_reading_events, :recorded_at
  end
end
