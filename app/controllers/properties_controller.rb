# frozen_string_literal: true

class PropertiesController < ApplicationController
  before_action :require_admin
  before_action :set_property, only: %i[show edit update archive]

  def index
    @properties = if params[:include_archived] == "true"
      Property.with_discarded.order(name: :asc)
    else
      Property.kept.order(name: :asc)
    end
  end

  def show; end

  def new
    @property = Property.new
  end

  def create
    @property = Property.new(property_params)

    if @property.save
      redirect_to properties_path, notice: t("properties.create.success", name: @property.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @property.update(property_params)
      redirect_to property_path(@property), notice: t("properties.update.success", name: @property.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    if @property.discard
      redirect_to properties_path, notice: t("properties.archive.success", name: @property.name)
    else
      redirect_to property_path(@property), alert: t("properties.archive.failure")
    end
  end

  private

  def set_property
    @property = Property.kept.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to properties_path, alert: t("properties.not_found")
  end

  def property_params
    params.require(:property).permit(:name, :address)
  end

  def require_admin
    unless current_user&.admin?
      redirect_to root_path, alert: t("users.admin_required")
    end
  end
end
