# frozen_string_literal: true

class Shared::IconComponent < ApplicationComponent
  def initialize(icon_class:, style: "solid", color: nil)
    @icon_class = icon_class
    @style = style
    @color = color
  end

  def css_classes
    classes = [ "fa-#{@style}", @icon_class ]
    classes << @color if @color.present?
    classes.join(" ")
  end
end
