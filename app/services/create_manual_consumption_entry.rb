# frozen_string_literal: true

# Service to create a manual consumption entry for a visitor.
#
# Use case UC3: Manual Consumption Entry
# Constraints: C7 (positive kWh), C8 (soft validation against period consumption)
#
# Example:
#   outcome = CreateManualConsumptionEntry.run(
#     visitor: visitor,
#     property: property,
#     date: Date.current,
#     kwh: 15.5,
#     note: "EV charging",
#     recorded_by_user: current_user
#   )
#
#   if outcome.valid?
#     entry = outcome.result
#     # Check for warnings
#     if outcome.errors[:consumption_warning].any?
#       # Display warning to user
#     end
#   else
#     # Handle validation errors
#   end
class CreateManualConsumptionEntry < ApplicationService
  # Inputs
  object :visitor, class: Visitor
  object :property, class: Property
  date :date
  float :kwh
  string :note
  object :recorded_by_user, class: User

  # Validations
  validate :kwh_must_be_positive
  validate :check_period_consumption_warning

  def execute
    entry = ManualConsumptionEntry.new(
      visitor: visitor,
      property: property,
      date: date,
      kwh: kwh,
      note: note,
      recorded_by_user: recorded_by_user
    )

    if entry.save
      entry
    else
      # Merge model validation errors into the interaction errors
      entry.errors.each do |error|
        errors.add(error.attribute, error.message)
      end
      nil
    end
  end

  private

  def kwh_must_be_positive
    # C7: Manual entries must have positive kWh values
    return if kwh.nil?

    errors.add(:kwh, "must be positive") if kwh <= 0
  end

  def check_period_consumption_warning
    # C8: Manual entry kWh should not exceed unattributed consumption in the enclosing period
    # This is a soft validation - adds a warning, not a blocking error
    #
    # TODO: Implement period consumption check once period analysis service is complete
    # 1. Find the period that contains this entry's date
    # 2. Calculate total_kwh for that period (main meter delta)
    # 3. Calculate manual_kwh already attributed in that period
    # 4. Calculate shared_kwh for present visitors in that period
    # 5. Calculate unattributed_kwh = total_kwh - manual_kwh - shared_kwh
    # 6. If kwh > unattributed_kwh, add a warning
    #
    # For now, this is a placeholder that does nothing.
    # When period analysis service exists, wire it up here.
    #
    # Example implementation:
    #   period = PeriodAnalysisService.find_period_for_date(property, date)
    #   return unless period
    #
    #   unattributed = period.unattributed_kwh
    #   if kwh > unattributed
    #     errors.add(:consumption_warning, "Manual entry (#{kwh} kWh) exceeds unattributed consumption (#{unattributed.round(2)} kWh) for this period")
    #   end
  end
end
