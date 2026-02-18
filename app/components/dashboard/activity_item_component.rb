# frozen_string_literal: true

class Dashboard::ActivityItemComponent < ApplicationComponent
  def initialize(type:, visitor_name:, action:, date:, details: nil)
    @type = type
    @visitor_name = visitor_name
    @action = action
    @date = date
    @details = details
  end

  attr_reader :type, :visitor_name, :action, :date, :details

  def icon_class
    case type
    when "check_in"
      "fa-right-to-bracket"
    when "check_out"
      "fa-right-from-bracket"
    when "manual_entry"
      "fa-bolt"
    else
      "fa-circle"
    end
  end

  def icon_color
    case type
    when "check_in"
      "text-green-500"
    when "check_out"
      "text-red-400"
    when "manual_entry"
      "text-yellow-500"
    else
      "text-gray-400"
    end
  end

  def formatted_date
    return "" unless date

    I18n.l(date.to_date, format: :short)
  end
end
