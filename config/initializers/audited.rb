# Configure Audited for audit trail
# Models that call `audited` will track changes
Audited.config do |config|
  # Store the current user who made the change
  config.current_user_method = :current_user
end
