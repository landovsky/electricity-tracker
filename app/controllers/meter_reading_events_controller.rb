# frozen_string_literal: true

# Deleting a meter reading event rewrites stays and allocation history, so per
# spec section 9 ("Edit / delete any record") it is admin-only, and only events
# of the current property can be targeted.
class MeterReadingEventsController < ApplicationController
  before_action :require_admin
  before_action :require_property

  def destroy
    event = MeterReadingEvent.kept
                             .joins(meter_readings: :meter)
                             .where(meters: { property_id: current_property.id })
                             .distinct
                             .find_by(id: params[:id])
    return redirect_to(readings_history_path, alert: t("meter_reading_events.destroy.not_found")) unless event

    outcome = DeleteMeterReadingEvent.run(event: event)

    if outcome.valid?
      flash.now[:notice] = t("meter_reading_events.destroy.success")
    else
      flash.now[:alert] = outcome.errors.full_messages.join(", ")
    end

    respond_to do |format|
      format.turbo_stream { render "destroy", locals: { event: event } }
      format.html { redirect_to readings_history_path, flash.to_h }
    end
  end

  private

  def require_admin
    return if current_user&.admin?

    redirect_to readings_history_path, alert: t("meter_reading_events.admin_required")
  end
end
