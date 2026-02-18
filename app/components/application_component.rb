# frozen_string_literal: true

# Base class for all ViewComponents in the application.
#
# ViewComponents are a framework for building reusable, testable & encapsulated view
# components in Rails. Each component is a Ruby class with an associated ERB template.
#
# Key benefits:
# - Components are easily unit-testable in isolation
# - Templates are scoped to their component (no accidental global state)
# - Better performance than partials (compiled Ruby instead of re-parsed ERB)
# - Type safety and validations via initialize parameters
#
# Usage:
#   class ButtonComponent < ApplicationComponent
#     def initialize(label:, variant: :primary)
#       @label = label
#       @variant = variant
#     end
#   end
#
# Then in views:
#   <%= render ButtonComponent.new(label: "Click me", variant: :secondary) %>
#
# Component templates live in app/components/button_component.html.erb
#
# See: https://viewcomponent.org/guide/
class ApplicationComponent < ViewComponent::Base
  include ValidationHelper
end
