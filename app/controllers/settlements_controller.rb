# frozen_string_literal: true

# Serves hand-made yearly electricity settlements (vyúčtování) as static pages to the
# family members of the property they belong to. The pages are generated outside the app
# (data/vyuctovani-*/calc/build.py) from the paper notebook + invoice, so this only gates
# access: they list names and amounts and must not be public.
#
# GET /vyuctovani/:property/:year           common page (all branches)
# GET /vyuctovani/:property/:year/:branch   one family branch with its members' split
class SettlementsController < ApplicationController
  REPORTS = {
    [ "sucha", "2026" ] => { property_subdomain: "sepot", path: "data/vyuctovani-2026/vyuctovani-sucha-2026.html",
                             branches: %w[jiri kristina petr] }
  }.freeze

  def show
    report = REPORTS[[ params[:property], params[:year] ]]
    raise ActionController::RoutingError, "Not Found" unless report
    raise ActionController::RoutingError, "Not Found" if params[:branch] && !report[:branches].include?(params[:branch])
    raise ActionController::RoutingError, "Not Found" unless current_user.accessible_properties.exists?(subdomain: report[:property_subdomain])

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    path = params[:branch] ? report[:path].sub(/\.html\z/, "-#{params[:branch]}.html") : report[:path]
    render html: Rails.root.join(path).read.html_safe, layout: false
  end
end
