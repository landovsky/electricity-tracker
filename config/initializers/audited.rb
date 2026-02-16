# Configure Audited for audit trail
# Models that call `audited` will track changes
Audited.config do |config|
  # Store the current user who made the change
  config.current_user_method = :current_user
end

# Configure Psych YAML serializer to allow Time classes
# This is needed for Audited gem compatibility with Rails 8 and Ruby 3.4
if defined?(ActiveRecord::Coders::YAMLColumn::SafeCoder)
  PERMITTED_YAML_CLASSES = [
    Symbol,
    Time,
    ActiveSupport::TimeWithZone,
    ActiveSupport::TimeZone,
    Date,
    DateTime,
    BigDecimal
  ].freeze

  module AuditedTimeWithZoneFix
    def dump(obj)
      # Use Psych.safe_dump with permitted_classes instead of the default
      if obj.nil?
        nil
      else
        Psych.safe_dump(obj, permitted_classes: PERMITTED_YAML_CLASSES, aliases: true)
      end
    end

    def load(yaml)
      # Use Psych.safe_load with permitted_classes instead of the default
      return unless yaml

      if yaml.is_a?(String) && /^---/.match?(yaml)
        Psych.safe_load(yaml, permitted_classes: PERMITTED_YAML_CLASSES, aliases: true) || {}
      else
        yaml
      end
    end
  end

  ActiveRecord::Coders::YAMLColumn::SafeCoder.prepend(AuditedTimeWithZoneFix)
end
