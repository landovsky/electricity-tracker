class CreatePropertyUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :property_users do |t|
      t.references :property, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :property_users, [ :property_id, :user_id ], unique: true
  end
end
