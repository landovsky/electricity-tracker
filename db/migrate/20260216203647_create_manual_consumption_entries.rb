class CreateManualConsumptionEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :manual_consumption_entries do |t|
      t.references :visitor, null: false, foreign_key: true
      t.references :property, null: false, foreign_key: true
      t.date :date, null: false
      t.decimal :kwh, precision: 10, scale: 2, null: false
      t.text :note, null: false
      t.bigint :recorded_by_user_id
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :manual_consumption_entries, :deleted_at
    add_index :manual_consumption_entries, :recorded_by_user_id
    add_index :manual_consumption_entries, :date
  end
end
