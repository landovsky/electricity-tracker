# frozen_string_literal: true

# Handles first-time user onboarding (name input).
# Shown after first login when user.name is blank (self-registered users).
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
        CreateDefaultVisitorForUser.run!(user: current_user)
        redirect_to root_path, notice: t("onboarding.success")
      else
        flash.now[:alert] = t("onboarding.name_required")
        render :show, status: :unprocessable_entity
      end
    end
  end
end
