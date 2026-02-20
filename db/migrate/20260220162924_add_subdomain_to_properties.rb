class AddSubdomainToProperties < ActiveRecord::Migration[8.1]
  def change
    add_column :properties, :subdomain, :string
    add_index :properties, :subdomain
  end
end
