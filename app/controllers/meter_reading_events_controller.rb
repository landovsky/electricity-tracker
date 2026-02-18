# frozen_string_literal: true

class MeterReadingEventsController < ApplicationController
  before_action :set_event

  def destroy
    if @event.check_in? && @event.stay_as_check_in&.check_out_event_id.present?
      redirect_to readings_history_path, alert: t("meter_reading_events.destroy.has_checkout")
      return
    end

    @event.discard
    redirect_to readings_history_path, notice: t("meter_reading_events.destroy.success")
  end

  private

  def set_event
    @event = MeterReadingEvent.kept.find(params[:id])
  end
end
