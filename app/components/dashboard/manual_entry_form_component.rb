# frozen_string_literal: true

class Dashboard::ManualEntryFormComponent < ApplicationComponent
  def initialize(visitors:, selected_visitor_id: nil)
    @visitors = visitors
    @selected_visitor_id = selected_visitor_id
  end

  attr_reader :visitors, :selected_visitor_id
end
