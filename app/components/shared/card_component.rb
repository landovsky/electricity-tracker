# frozen_string_literal: true

class Shared::CardComponent < ApplicationComponent
  def initialize(title:, header_action: nil)
    @title = title
    @header_action = header_action
  end

  attr_reader :title, :header_action
end
