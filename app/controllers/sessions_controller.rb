# frozen_string_literal: true

# Handles magic link authentication flow.
#
# Flow:
# 1. GET  /login       → Show login form (email input)
# 2. POST /login       → Generate token, send magic link email
# 3. GET  /auth/:token → Verify token, create session
# 4. DELETE /logout     → Destroy session
class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create verify]

  def new
    redirect_to root_path if logged_in?
  end

  def create
    email = params[:email].to_s.strip.downcase
    user = User.kept.find_by(email: email)

    if user
      token = GenerateMagicLinkToken.run!(user: user)
      MagicLinkMailer.login_link(user: user, token: token).deliver_later
    end

    # Always show same message to prevent user enumeration
    redirect_to login_path, notice: t("sessions.create.notice")
  end

  def verify
    outcome = VerifyMagicLinkToken.run(token: params[:token])

    if outcome.valid? && outcome.result
      session[:user_id] = outcome.result.id
      redirect_to root_path, notice: t("sessions.verify.success")
    else
      redirect_to login_path, alert: t("sessions.verify.failure")
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t("sessions.destroy.notice")
  end
end
