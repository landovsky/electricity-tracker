# frozen_string_literal: true

# Handles authentication via email magic link or SMS OTP.
#
# Email flow:
# 1. GET  /login            → Show login form (email/SMS choice)
# 2. POST /login            → Find/create user, send magic link email
# 3. GET  /login/email_sent → Info page: "check your email"
# 4. GET  /auth/:token      → Verify token, create session
#
# SMS flow:
# 1. GET  /login            → Show login form (email/SMS choice)
# 2. POST /login/sms        → Find/create user, send OTP via SMS
# 3. GET  /login/verify_otp → Show OTP input form
# 4. POST /login/verify_otp → Verify OTP, create session
#
# 5. DELETE /logout          → Destroy session
class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create email_sent create_sms otp_form verify_otp verify]
  skip_before_action :require_onboarding, only: %i[new create email_sent create_sms otp_form verify_otp verify destroy]

  def new
    redirect_to root_path if logged_in?
  end

  # POST /login — Email magic link flow
  def create
    email = params[:email].to_s.strip.downcase
    user = FindOrCreateUserByEmail.run(email: email)

    if user.valid? && user.result
      token = GenerateMagicLinkToken.run!(user: user.result)
      MagicLinkMailer.login_link(user: user.result, token: token).deliver_later
    end

    # Always redirect to email_sent page to prevent user enumeration
    redirect_to email_sent_path
  end

  # GET /login/email_sent — Info page after email submission
  def email_sent
    redirect_to root_path if logged_in?
  end

  # POST /login/sms — SMS OTP flow
  def create_sms
    unless verify_recaptcha(action: "sms_login", minimum_score: 0.5, secret_key: ENV["RECAPTCHA_SECRET_KEY"])
      score = recaptcha_reply&.dig("score")
      Rails.logger.warn("reCAPTCHA failed for SMS login – score: #{score}, errors: #{recaptcha_reply&.dig("error-codes")}")

      if Rails.env.development?
        flash[:alert] = "reCAPTCHA failed (dev – pokračujeme). Score: #{score}"
      else
        redirect_to login_path, alert: t("sessions.sms.recaptcha_failed")
        return
      end
    end

    # Store score for debugging regardless of pass/fail
    captcha_score = recaptcha_reply&.dig("score")

    phone = params[:phone_number].to_s.strip
    outcome = FindOrCreateUserByPhone.run(phone_number: phone)

    unless outcome.valid? && outcome.result
      redirect_to login_path, alert: t("sessions.sms.invalid_phone")
      return
    end

    user = outcome.result
    user.update_column(:recaptcha_score, captcha_score) if captcha_score

    code = GenerateSmsOtp.run!(user: user)
    SendSmsMessage.run(
      phone_number: user.phone_number,
      body: t("sessions.sms.otp_message", code: code)
    )

    session[:pending_sms_user_id] = user.id
    redirect_to otp_form_path
  end

  # GET /login/verify_otp — Show OTP input form
  def otp_form
    redirect_to login_path unless session[:pending_sms_user_id]
  end

  # POST /login/verify_otp — Verify OTP code
  def verify_otp
    user = User.kept.find_by(id: session[:pending_sms_user_id])

    unless user
      redirect_to login_path, alert: t("sessions.sms.session_expired")
      return
    end

    outcome = VerifySmsOtp.run(user: user, code: params[:code].to_s.strip)

    if outcome.valid? && outcome.result
      session.delete(:pending_sms_user_id)
      session[:user_id] = outcome.result.id
      redirect_to after_login_path(outcome.result), notice: t("sessions.verify.success")
    else
      redirect_to otp_form_path, alert: t("sessions.sms.invalid_code")
    end
  end

  # GET /auth/:token — Email magic link verification
  def verify
    outcome = VerifyMagicLinkToken.run(token: params[:token])

    if outcome.valid? && outcome.result
      session[:user_id] = outcome.result.id
      redirect_to after_login_path(outcome.result), notice: t("sessions.verify.success")
    else
      redirect_to login_path, alert: t("sessions.verify.failure")
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t("sessions.destroy.notice")
  end

  private

  def after_login_path(user)
    ensure_default_visitor(user) if user.onboarded?
    user.onboarded? ? root_path : onboarding_path
  end

  def ensure_default_visitor(user)
    return if user.default_visitor_id.present?

    CreateDefaultVisitorForUser.run(user: user)
  end
end
