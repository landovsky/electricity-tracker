class AddDefaultVisitorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :default_visitor, foreign_key: { to_table: :visitors }, null: true
  end
end
