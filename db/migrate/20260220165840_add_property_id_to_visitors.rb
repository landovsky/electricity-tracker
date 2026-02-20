class AddPropertyIdToVisitors < ActiveRecord::Migration[8.1]
  def up
    # Step 1: Add nullable property_id column
    add_reference :visitors, :property, foreign_key: true, null: true

    # Step 2: Backfill existing visitors
    Visitor.reset_column_information

    Visitor.find_each do |visitor|
      # Try to find property from visitor's stays
      stay = Stay.where(visitor_id: visitor.id).first
      if stay
        visitor.update_column(:property_id, stay.property_id)
      else
        # Orphaned visitor: find the User whose default_visitor_id points to them
        user = User.find_by(default_visitor_id: visitor.id)
        if user
          property_user = PropertyUser.find_by(user_id: user.id)
          if property_user
            visitor.update_column(:property_id, property_user.property_id)
          else
            visitor.update_column(:property_id, Property.first&.id)
          end
        else
          visitor.update_column(:property_id, Property.first&.id)
        end
      end
    end

    # Step 3: Add NOT NULL constraint
    change_column_null :visitors, :property_id, false
  end

  def down
    remove_reference :visitors, :property
  end
end
