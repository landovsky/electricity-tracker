# frozen_string_literal: true

class AddMultiTariffMeterSupport < ActiveRecord::Migration[8.1]
  def change
    # Add meter_group column to group registers of the same physical meter
    add_column :meters, :meter_group, :string

    # Add index for querying meters by property and group
    add_index :meters, [:property_id, :meter_group], name: "index_meters_on_property_id_and_meter_group"

    # Remove the unique index on [meter_type, property_id] if it exists
    # SQLite doesn't have a named unique index for validates uniqueness,
    # but the model validation was the constraint — no DB-level unique index to remove.
  end
end
