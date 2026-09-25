# frozen_string_literal: true

# Handles first-time user onboarding (name input).
# Shown after first login when user.name is blank (self-registered users).
#
# Completing onboarding is what finishes self-registration: the user only gets
# the default property (and their Visitor) here, after the login has been
# verified — never on the unauthenticated login POST.
class OnboardingController < ApplicationController
  skip_before_action :require_onboarding

  def show
    redirect_to root_path if current_user.onboarded?
  end

  def update
    name = params[:name].to_s.strip

    if name.blank?
      flash.now[:alert] = t("onboarding.name_required")
      render :show, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      if current_user.update(name: name)
        AssignDefaultProperty.run!(user: current_user) if current_user.properties.empty?
        current_user.reload
        rename_placeholder_default_visitor(current_user)
        CreateDefaultVisitorForUser.run!(user: current_user)
        redirect_to root_path, notice: t("onboarding.success")
      else
        flash.now[:alert] = t("onboarding.name_required")
        render :show, status: :unprocessable_entity
      end
    end
  end

  private

  # Users registered before property assignment moved here already have a
  # Visitor auto-named after their email (or "User #id" for phone sign-ups).
  # Give it the name they just entered instead of keeping the placeholder.
  def rename_placeholder_default_visitor(user)
    visitor = user.default_visitor
    return unless visitor

    placeholders = [ user.email, "User ##{user.id}" ].compact
    visitor.update!(name: user.name) if placeholders.include?(visitor.name)
  end
end
