class CreateStays < ActiveRecord::Migration[8.1]
  def change
    create_table :stays do |t|
      t.references :visitor, null: false, foreign_key: true
      t.references :property, null: false, foreign_key: true
      t.bigint :check_in_event_id
      t.bigint :check_out_event_id
      t.text :note
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :stays, :deleted_at
    add_index :stays, :check_in_event_id
    add_index :stays, :check_out_event_id
  end
end
