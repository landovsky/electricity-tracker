# frozen_string_literal: true

class Dashboard::ManualEntryFormComponent < ApplicationComponent
  def initialize(visitors:)
    @visitors = visitors
  end

  attr_reader :visitors
end
