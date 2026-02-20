# frozen_string_literal: true

class MetersController < ApplicationController
  before_action :require_admin
  before_action :set_property
  before_action :set_meter, only: %i[edit update]

  def new
    @meter = @property.meters.build(meter_type: "main", unit: "kWh")
  end

  def create
    @meter = @property.meters.build(meter_params)

    ActiveRecord::Base.transaction do
      @meter.save!

      if params[:initial_reading].present?
        event = MeterReadingEvent.create!(
          event_type: "initial",
          recorded_at: Time.current,
          recorded_by_user: current_user
        )
        event.meter_readings.create!(
          meter: @meter,
          value_kwh: params[:initial_reading]
        )
      end
    end

    redirect_to property_path(@property), notice: t("meters.create.success", label: @meter.label)
  rescue ActiveRecord::RecordInvalid => e
    @meter.errors.add(:base, e.message) unless @meter.errors.any?
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    if @meter.update(meter_params)
      redirect_to property_path(@property), notice: t("meters.update.success", label: @meter.label)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_property
    @property = Property.kept.find(params[:property_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to properties_path, alert: t("properties.not_found")
  end

  def set_meter
    @meter = @property.meters.kept.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to property_path(@property), alert: t("meters.not_found")
  end

  def meter_params
    params.require(:meter).permit(:label, :meter_type, :unit, :meter_group)
  end

  def require_admin
    unless current_user&.admin?
      redirect_to root_path, alert: t("users.admin_required")
    end
  end
end
