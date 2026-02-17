class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # Disabled in test environment to allow request specs to run
  allow_browser versions: :modern unless Rails.env.test?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_authentication

  helper_method :current_user, :logged_in?

  private

  def current_user
    @current_user ||= if session[:user_id]
      User.kept.find_by(id: session[:user_id])
    elsif auth_disabled?
      User.kept.first
    end
  end

  def logged_in?
    current_user.present?
  end

  def require_authentication
    return if auth_disabled?
    return if logged_in?

    redirect_to login_path, alert: t("auth.login_required")
  end

  def auth_disabled?
    ENV["DISABLE_AUTH"] == "true"
  end
end
