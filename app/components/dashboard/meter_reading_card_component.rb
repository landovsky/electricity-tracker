# frozen_string_literal: true

class Dashboard::MeterReadingCardComponent < ApplicationComponent
  def initialize(label:, value:, date:, icon_class: "fa-gauge-high")
    @label = label
    @value = value
    @date = date
    @icon_class = icon_class
  end

  attr_reader :label, :value, :date, :icon_class

  def formatted_value
    helpers.number_with_delimiter(value)
  end

  def formatted_date
    date.strftime("%b %d") if date
  end
end
