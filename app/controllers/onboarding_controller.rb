# frozen_string_literal: true

# Handles first-time user onboarding (name input).
# Shown after first login when user.name is blank (self-registered users).
class OnboardingController < ApplicationController
  skip_before_action :require_onboarding

  def show
    redirect_to root_path if current_user.onboarded?
  end

  def update
    if current_user.update(name: params[:name].to_s.strip)
      redirect_to root_path, notice: t("onboarding.success")
    else
      flash.now[:alert] = t("onboarding.name_required")
      render :show, status: :unprocessable_entity
    end
  end
end
