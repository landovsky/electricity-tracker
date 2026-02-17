# frozen_string_literal: true

class Dashboard::ActionFormsComponent < ApplicationComponent
  def initialize(visitors_for_checkin:, visitors_for_checkout:, meters:, last_readings:)
    @visitors_for_checkin = visitors_for_checkin
    @visitors_for_checkout = visitors_for_checkout
    @meters = meters
    @last_readings = last_readings
  end

  attr_reader :visitors_for_checkin, :visitors_for_checkout, :meters, :last_readings

  # All visitors for manual entry form
  def all_visitors
    (visitors_for_checkin + visitors_for_checkout).uniq
  end

  def default_tab
    "checkin"
  end
end
