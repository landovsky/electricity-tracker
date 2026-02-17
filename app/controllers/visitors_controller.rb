# frozen_string_literal: true

# Controller for visitor management (CRUD).
#
# Implements visitor lifecycle operations:
# - List all visitors (with optional archived filter)
# - View visitor details with stay history
# - Create new visitors
# - Update visitor information
# - Archive (soft delete) visitors
#
# Permissions:
# - Members: can view and create visitors
# - Admins: can edit and archive visitors
class VisitorsController < ApplicationController
  before_action :set_visitor, only: %i[show edit update archive]
  before_action :require_admin, only: %i[edit update archive]

  # GET /visitors
  # Lists all visitors with optional archived filter
  def index
    @visitors = Visitor.kept.order(name: :asc)

    # Include archived visitors if requested
    if params[:include_archived] == "true"
      @visitors = Visitor.with_discarded.order(name: :asc)
    end
  end

  # GET /visitors/:id
  # Shows visitor details with stay history
  def show
    @stays = @visitor.stays.kept.order(created_at: :desc).includes(:check_in_event, :check_out_event)
    @manual_entries = @visitor.manual_consumption_entries.kept.order(date: :desc)
  end

  # GET /visitors/new
  # Form to create a new visitor
  def new
    @visitor = Visitor.new
  end

  # POST /visitors
  # Creates a new visitor
  def create
    @visitor = Visitor.new(visitor_params)

    if @visitor.save
      redirect_to visitors_path, notice: t("visitors.create.success", name: @visitor.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /visitors/:id/edit
  # Form to edit visitor information
  def edit
    # @visitor set by before_action
  end

  # PATCH/PUT /visitors/:id
  # Updates visitor information
  def update
    if @visitor.update(visitor_params)
      redirect_to visitor_path(@visitor), notice: t("visitors.update.success", name: @visitor.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # PATCH /visitors/:id/archive
  # Soft deletes (archives) a visitor
  def archive
    if @visitor.discard
      redirect_to visitors_path, notice: t("visitors.archive.success", name: @visitor.name)
    else
      redirect_to visitor_path(@visitor), alert: t("visitors.archive.failure")
    end
  end

  private

  def set_visitor
    @visitor = Visitor.kept.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to visitors_path, alert: t("visitors.not_found")
  end

  def visitor_params
    params.require(:visitor).permit(:name, :status, :note)
  end

  def require_admin
    unless current_user&.admin?
      redirect_to visitors_path, alert: t("visitors.admin_required")
    end
  end
end
