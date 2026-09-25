# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :require_admin
  before_action :set_user, only: %i[show edit update archive]

  def index
    @users = if params[:include_archived] == "true"
      User.with_discarded.order(name: :asc)
    else
      User.kept.order(name: :asc)
    end
  end

  def show; end

  def new
    @user = User.new
    @visitors = current_property.visitors.kept.active.order(name: :asc)
  end

  def create
    @user = User.new(user_params)

    if save_with_property_access(@user)
      redirect_to users_path, notice: t("users.create.success", name: @user.name)
    else
      @visitors = current_property.visitors.kept.active.order(name: :asc)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @visitors = current_property.visitors.kept.active.order(name: :asc)
  end

  def update
    if @user.update(user_params)
      redirect_to user_path(@user), notice: t("users.update.success", name: @user.name)
    else
      @visitors = current_property.visitors.kept.active.order(name: :asc)
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    if @user.discard
      redirect_to users_path, notice: t("users.archive.success", name: @user.name)
    else
      redirect_to user_path(@user), alert: t("users.archive.failure")
    end
  end

  private

  # An admin-created member skips onboarding (the admin already set the
  # name), so this is where they get property access: the property of the
  # chosen default visitor, otherwise the property the admin is working in.
  # Without it the member would log in to a dashboard with no property.
  def save_with_property_access(user)
    User.transaction do
      next false unless user.save

      property = user.default_visitor&.property || current_property
      user.properties << property if property
      true
    end
  end

  def set_user
    @user = User.kept.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to users_path, alert: t("users.not_found")
  end

  def user_params
    params.require(:user).permit(:name, :email, :phone_number, :role, :default_visitor_id)
  end

  def require_admin
    unless current_user&.admin?
      redirect_to root_path, alert: t("users.admin_required")
    end
  end
end
