# frozen_string_literal: true

# Service to soft-delete a meter reading event.
#
# Enforces constraints:
# - Check-in events cannot be deleted if a check-out event exists for the same stay
#
# Nullifies stay references before discarding the event.
class DeleteMeterReadingEvent < ApplicationService
  object :event, class: MeterReadingEvent

  validate :validate_no_checkout_exists

  def execute
    if event.check_in? && event.stay_as_check_in&.open?
      event.stay_as_check_in.discard!
    elsif event.check_out? && event.stay_as_check_out
      Stay.where(id: event.stay_as_check_out.id).update_all(check_out_event_id: nil)
    end

    event.discard!
    event
  end

  private

  def validate_no_checkout_exists
    return unless event.check_in?
    return unless event.stay_as_check_in&.check_out_event_id.present?

    errors.add(:base, I18n.t("meter_reading_events.destroy.has_checkout"))
  end
end
