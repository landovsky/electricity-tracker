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
#     # C8 soft validation: entry is saved, but may carry a warning
#     flash[:warning] = outcome.consumption_warning if outcome.consumption_warning
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
  validate :visitor_must_belong_to_property

  # C8 soft validation result. Set after a successful save; never an error,
  # because an error would make the outcome invalid and block the entry.
  attr_reader :consumption_warning

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
      @consumption_warning = period_consumption_warning(entry)
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

    errors.add(:kwh, I18n.t("services.create_manual_consumption_entry.kwh_not_positive")) if kwh <= 0
  end

  # A manual entry booked under another property's visitor would pull kWh out
  # of this property's shared pool and bill it to someone who was never here.
  def visitor_must_belong_to_property
    return unless visitor && property
    return if visitor.property_id == property.id

    errors.add(:visitor, :invalid)
  end

  # C8: warn when the manual entries of the enclosing period (including this
  # one) exceed what the main meter measured in that period, i.e. this entry
  # exceeds the consumption still unattributed to other manual entries.
  #
  # The enclosing period uses AnalyzePeriods' own rule: an entry dated D belongs
  # to the period whose start event is on or before D and whose end event is on
  # a later day. The end event is therefore the first event from D+1 onwards and
  # the first event of its own day, so analysing just that day (plus the boundary
  # event AnalyzePeriods prepends) yields the enclosing period first.
  #
  # When no event exists after D yet, the period is still open and cannot be
  # checked.
  def period_consumption_warning(entry)
    period = enclosing_period(entry.date)
    return nil unless period

    manual_kwh = period[:manual_entries].sum(&:kwh)
    return nil if manual_kwh <= period[:primary_delta]

    I18n.t("activerecord.errors.models.manual_consumption_entry.attributes.kwh.exceeds_period",
           kwh: entry.kwh,
           available: [ period[:primary_delta] - (manual_kwh - entry.kwh), 0 ].max.to_f.round(2))
  end

  def enclosing_period(entry_date)
    end_event_at = MeterReadingEvent.kept
                                    .joins(meter_readings: :meter)
                                    .where(meters: { property_id: property.id })
                                    .where("meter_reading_events.recorded_at >= ?", (entry_date + 1).in_time_zone.beginning_of_day)
                                    .minimum(:recorded_at)
    return nil unless end_event_at

    end_day = end_event_at.in_time_zone.to_date
    outcome = AnalyzePeriods.run(property: property, date_range: { start_date: end_day, end_date: end_day })
    return nil unless outcome.valid?

    outcome.result.find do |period|
      period[:start_time].to_date <= entry_date && entry_date < period[:end_time].to_date
    end
  end
end
