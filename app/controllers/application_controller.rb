class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # Disabled in test environment to allow request specs to run
  allow_browser versions: :modern unless Rails.env.test?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_authentication
  before_action :require_onboarding

  helper_method :current_user, :logged_in?, :current_property, :available_properties

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

  # Returns the currently selected property for the logged-in user.
  # Falls back to first accessible property if session value is stale or missing.
  def current_property
    return @current_property if defined?(@current_property)

    props = available_properties
    @current_property = if session[:property_id].present?
      props.find_by(id: session[:property_id]) || props.first
    else
      props.first
    end

    # Keep session in sync
    session[:property_id] = @current_property&.id
    @current_property
  end

  # Properties available to the current user, filtered by subdomain when present.
  # When accessing sucha.kopernici.cz, only properties with subdomain "sucha" are shown.
  # When accessing bare kopernici.cz (no subdomain), all user's properties are available.
  def available_properties
    return Property.none unless current_user

    @available_properties ||= begin
      props = current_user.accessible_properties
      sub = request.subdomain.presence
      sub ? props.where(subdomain: sub) : props
    end
  end

  def require_authentication
    return if auth_disabled?
    return if logged_in?

    redirect_to login_path, alert: t("auth.login_required")
  end

  def require_onboarding
    return unless logged_in?
    return if current_user.onboarded?

    redirect_to onboarding_path
  end

  def auth_disabled?
    ENV["DISABLE_AUTH"] == "true"
  end
end
