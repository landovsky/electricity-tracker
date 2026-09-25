# Logins used to grant property access (AssignDefaultProperty on first login).
# That grant was removed so a login can no longer undo an admin revoke, which
# left users created before the change — who never logged in — with no
# PropertyUser at all and therefore locked out.
#
# Grant each kept user with ZERO property_users the kept property their
# default visitor lives on. Plain SQL on purpose: PropertyUser#after_create
# would create visitors, and the user already has theirs. Idempotent: users
# who already have any property_users row are skipped.
class BackfillPropertyAccessForPendingUsers < ActiveRecord::Migration[8.1]
  BACKFILL_SQL = <<~SQL.squish
    INSERT INTO property_users (user_id, property_id, created_at, updated_at)
    SELECT users.id, visitors.property_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    FROM users
    INNER JOIN visitors ON visitors.id = users.default_visitor_id
    INNER JOIN properties ON properties.id = visitors.property_id
    WHERE users.deleted_at IS NULL
      AND properties.deleted_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM property_users existing WHERE existing.user_id = users.id
      )
  SQL

  def up
    execute BACKFILL_SQL
  end

  def down
    # Irreversible data fix; rolling back leaves the granted access in place.
  end
end
