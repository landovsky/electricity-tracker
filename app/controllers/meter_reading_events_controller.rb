# frozen_string_literal: true

class MeterReadingEventsController < ApplicationController
  def destroy
    event = MeterReadingEvent.kept.find(params[:id])
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
end
