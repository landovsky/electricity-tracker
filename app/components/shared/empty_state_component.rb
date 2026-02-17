# frozen_string_literal: true

class Shared::EmptyStateComponent < ApplicationComponent
  def initialize(message:, icon_class: nil)
    @message = message
    @icon_class = icon_class
  end

  attr_reader :message, :icon_class
end
