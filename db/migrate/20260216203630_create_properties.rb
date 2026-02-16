class CreateProperties < ActiveRecord::Migration[8.1]
  def change
    create_table :properties do |t|
      t.string :name
      t.text :address
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :properties, :deleted_at
  end
end
