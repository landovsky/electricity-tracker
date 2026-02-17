# frozen_string_literal: true

class Dashboard::VisitorCardComponent < ApplicationComponent
  def initialize(visitor:, checked_in_at:, stay_id:)
    @visitor = visitor
    @checked_in_at = checked_in_at
    @stay_id = stay_id
  end

  attr_reader :visitor, :checked_in_at, :stay_id

  def formatted_checkin_date
    return I18n.t("dashboard.visitor_card.recently") unless checked_in_at

    I18n.t("dashboard.visitor_card.since", date: I18n.l(checked_in_at.to_date, format: :short))
  end
end
