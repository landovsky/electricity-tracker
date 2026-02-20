# frozen_string_literal: true

class Dashboard::ActionFormsComponent < ApplicationComponent
  def initialize(visitors_for_checkin:, visitors_for_checkout:, meters:, last_readings:, default_visitor_id: nil, prefilled_readings: {}, camera_detections: [], default_tab: "checkin")
    @visitors_for_checkin = visitors_for_checkin
    @visitors_for_checkout = visitors_for_checkout
    @meters = meters
    @last_readings = last_readings
    @default_visitor_id = default_visitor_id
    @prefilled_readings = prefilled_readings
    @camera_detections = camera_detections
    @default_tab = default_tab
  end

  attr_reader :visitors_for_checkin, :visitors_for_checkout, :meters, :last_readings, :default_visitor_id, :prefilled_readings, :camera_detections, :default_tab

  # All visitors for manual entry form
  def all_visitors
    (visitors_for_checkin + visitors_for_checkout).uniq
  end
end
