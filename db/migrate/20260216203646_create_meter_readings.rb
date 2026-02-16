class CreateMeterReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :meter_readings do |t|
      t.references :meter_reading_event, null: false, foreign_key: true
      t.references :meter, null: false, foreign_key: true
      t.decimal :value_kwh, precision: 10, scale: 2, null: false
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :meter_readings, :deleted_at
  end
end
