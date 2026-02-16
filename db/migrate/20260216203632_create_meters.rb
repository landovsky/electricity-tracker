class CreateMeters < ActiveRecord::Migration[8.1]
  def change
    create_table :meters do |t|
      t.references :property, null: false, foreign_key: true
      t.string :meter_type
      t.string :label
      t.string :unit
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :meters, :deleted_at
  end
end
