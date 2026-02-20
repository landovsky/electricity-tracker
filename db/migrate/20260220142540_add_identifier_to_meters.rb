class AddIdentifierToMeters < ActiveRecord::Migration[8.1]
  def change
    add_column :meters, :identifier, :string
  end
end
