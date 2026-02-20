class AddTrackingModeToProperties < ActiveRecord::Migration[8.1]
  def change
    add_column :properties, :tracking_mode, :string, default: "visitors", null: false
  end
end
