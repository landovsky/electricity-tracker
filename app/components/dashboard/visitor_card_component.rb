# frozen_string_literal: true

class Dashboard::VisitorCardComponent < ApplicationComponent
  def initialize(visitor:, checked_in_at:)
    @visitor = visitor
    @checked_in_at = checked_in_at
  end

  attr_reader :visitor, :checked_in_at

  def formatted_checkin_date
    return "recently" unless checked_in_at

    "since #{checked_in_at.strftime('%b %d')}"
  end
end
