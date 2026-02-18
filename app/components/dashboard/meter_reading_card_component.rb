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
    I18n.l(date.to_date, format: :short) if date
  end
end
