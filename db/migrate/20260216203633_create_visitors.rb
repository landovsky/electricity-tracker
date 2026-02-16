class CreateVisitors < ActiveRecord::Migration[8.1]
  def change
    create_table :visitors do |t|
      t.string :name
      t.string :status
      t.text :note
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :visitors, :deleted_at
  end
end
