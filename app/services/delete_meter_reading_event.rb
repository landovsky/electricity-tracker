# frozen_string_literal: true

# Service to soft-delete a meter reading event.
#
# Enforces constraints:
# - Check-in events cannot be deleted if a check-out event exists for the same stay
# - Check-out events cannot be deleted if the visitor has another open or a later
#   stay: reopening the stay would give the visitor two open stays (C2) and bill
#   them for the time they were away
#
# Deleting a check-in discards its (open) stay; deleting a check-out reopens its
# stay. The event's readings are discarded with it so they stop counting as the
# meter's last reading. Everything happens in one transaction.
class DeleteMeterReadingEvent < ApplicationService
  object :event, class: MeterReadingEvent

  validate :validate_no_checkout_exists
  validate :validate_no_later_stay

  def execute
    ActiveRecord::Base.transaction do
      if event.check_in? && event.stay_as_check_in&.open?
        event.stay_as_check_in.discard!
      elsif event.check_out? && event.stay_as_check_out
        # update! (not update_all) so C2 runs as a backstop and the change is audited
        event.stay_as_check_out.update!(check_out_event: nil)
        # Forget the loaded has_one, otherwise saving the event below autosaves it
        # and writes check_out_event_id back.
        event.association(:stay_as_check_out).reset
      end

      event.meter_readings.kept.update_all(deleted_at: Time.current)
      event.discard!
    end

    event
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.join(", "))
    nil
  end

  private

  def validate_no_checkout_exists
    return unless event.check_in?
    return unless event.stay_as_check_in&.check_out_event_id.present?

    errors.add(:base, I18n.t("meter_reading_events.destroy.has_checkout"))
  end

  def validate_no_later_stay
    return unless event.check_out?

    stay = event.stay_as_check_out
    return unless stay

    other_stays = Stay.live.where(visitor_id: stay.visitor_id).where.not(id: stay.id)
    later_stays = other_stays.joins(:check_in_event)
                             .where("meter_reading_events.recorded_at >= ?", event.recorded_at)

    return unless other_stays.open.exists? || later_stays.exists?

    errors.add(:base, I18n.t("meter_reading_events.destroy.has_later_stay"))
  end
end
