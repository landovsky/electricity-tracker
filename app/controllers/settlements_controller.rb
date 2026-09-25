# frozen_string_literal: true

# Serves hand-made yearly electricity settlements (vyúčtování) as static pages to the
# family members of the property they belong to. The pages are generated outside the app
# (data/vyuctovani-*/calc/build.py) from the paper notebook + invoice, so this only gates
# access: they list names and amounts and must not be public.
#
# GET /vyuctovani/:property/:year
class SettlementsController < ApplicationController
  REPORTS = {
    [ "sucha", "2026" ] => { property_subdomain: "sepot", path: "data/vyuctovani-2026/vyuctovani-sucha-2026.html" }
  }.freeze

  def show
    report = REPORTS[[ params[:property], params[:year] ]]
    raise ActionController::RoutingError, "Not Found" unless report
    raise ActionController::RoutingError, "Not Found" unless current_user.accessible_properties.exists?(subdomain: report[:property_subdomain])

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    render html: Rails.root.join(report[:path]).read.html_safe, layout: false
  end
end
