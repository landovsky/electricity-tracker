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

require "ostruct"

class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create email_sent create_sms otp_form verify_otp verify]
  skip_before_action :require_onboarding, only: %i[new create email_sent create_sms otp_form verify_otp verify destroy]

  # Throttling for the unauthenticated login endpoints. Each of them either
  # sends a mail/SMS on our account or checks a secret, so an unthrottled
  # script could spam inboxes, burn the SMTP/SMS quota or guess OTP codes.
  # A dedicated in-process store is used: production runs a single replica,
  # and the app-wide cache is a null store in tests.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 10, within: 10.minutes, only: :create, store: RATE_LIMIT_STORE,
    with: -> { throttled! }
  rate_limit to: 3, within: 10.minutes, only: :create, store: RATE_LIMIT_STORE, name: "email",
    by: -> { params[:email].to_s.strip.downcase }, with: -> { throttled! }
  rate_limit to: 5, within: 10.minutes, only: :create_sms, store: RATE_LIMIT_STORE,
    with: -> { throttled! }
  rate_limit to: 10, within: 10.minutes, only: :verify_otp, store: RATE_LIMIT_STORE,
    with: -> { throttled! }

  def new
    redirect_to root_path if logged_in?
  end

  # POST /login — Email magic link flow
  def create
    email = params[:email].to_s.strip.downcase
    user = FindOrCreateUserByEmail.run(email: email)

    if user.valid? && user.result
      token = GenerateMagicLinkToken.run!(user: user.result)
      MagicLinkMailer.login_link(user: user.result, token: token, origin_host: magic_link_host).deliver_now
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
      score = recaptcha_reply&.score
      Rails.logger.warn("reCAPTCHA failed for SMS login – score: #{score}, errors: #{recaptcha_reply&.error_codes}")

      if Rails.env.development?
        flash[:alert] = "reCAPTCHA failed (dev – pokračujeme). Score: #{score}"
      else
        redirect_to login_path, alert: t("sessions.sms.recaptcha_failed")
        return
      end
    end

    # Store score for debugging regardless of pass/fail
    captcha_score = recaptcha_reply&.score

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
    elsif outcome.errors.added?(:code, :too_many_attempts)
      session.delete(:pending_sms_user_id)
      redirect_to login_path, alert: t("sessions.sms.too_many_attempts")
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
    # Kill any magic link still sitting in the user's inbox or browser history.
    current_user&.update_column(:magic_link_nonce, nil)
    reset_session
    redirect_to login_path, notice: t("sessions.destroy.notice")
  end

  private

  # Property access is not (re)granted here: new users get their default
  # property when they finish onboarding, and an onboarded user without any
  # property has had access removed by an admin, which a login must not undo.
  def after_login_path(user)
    ensure_default_visitor(user) if user.onboarded?
    user.onboarded? ? root_path : onboarding_path
  end

  # Keep the emailed link on the host the user logged in from (sepot vs
  # tymlova), but only for allowlisted hosts; anything else falls back to the
  # mailer's default (APP_HOST) so a forged Host/X-Forwarded-Host header can
  # never put a login token on an attacker's domain.
  def magic_link_host
    allowed = Rails.configuration.x.app_hosts
    return request.host if allowed.blank?

    request.host if allowed.include?(request.host)
  end

  def throttled!
    redirect_to login_path, alert: t("sessions.throttled")
  end

  def ensure_default_visitor(user)
    return if user.default_visitor_id.present?

    CreateDefaultVisitorForUser.run(user: user)
  end
end
