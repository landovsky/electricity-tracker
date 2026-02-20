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
    @users = User.kept.order(name: :asc)
  end

  def create
    @property = Property.new(property_params)

    if @property.save
      sync_user_ids(@property, params[:property][:user_ids])
      redirect_to properties_path, notice: t("properties.create.success", name: @property.name)
    else
      @users = User.kept.order(name: :asc)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @users = User.kept.order(name: :asc)
  end

  def update
    if @property.update(property_params)
      sync_user_ids(@property, params[:property][:user_ids])
      redirect_to property_path(@property), notice: t("properties.update.success", name: @property.name)
    else
      @users = User.kept.order(name: :asc)
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

  # Sync the allowed users for a property from checkbox form input.
  # Accepts an array of user ID strings (from checkboxes).
  def sync_user_ids(property, user_ids)
    user_ids = Array(user_ids).reject(&:blank?).map(&:to_i)
    property.user_ids = user_ids
  end

  def require_admin
    unless current_user&.admin?
      redirect_to root_path, alert: t("users.admin_required")
    end
  end
end
