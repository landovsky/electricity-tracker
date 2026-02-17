# frozen_string_literal: true

class Shared::ButtonComponent < ApplicationComponent
  def initialize(label:, variant: "primary", url: nil, method: :get)
    @label = label
    @variant = variant
    @url = url
    @method = method
  end

  attr_reader :label, :url, :method

  def css_classes
    base = "font-medium text-sm rounded-lg transition-colors"

    case @variant
    when "primary"
      "#{base} bg-brand-600 text-white py-3 px-4 hover:bg-brand-700 active:bg-brand-800"
    when "secondary"
      "#{base} bg-white border border-gray-200 text-gray-700 px-3 py-1.5 hover:bg-gray-50 active:bg-gray-100"
    when "danger"
      "#{base} bg-red-600 text-white py-3 px-4 hover:bg-red-700 active:bg-red-800"
    else
      base
    end
  end
end
