# frozen_string_literal: true

# RSpec configuration for ViewComponent testing.
#
# ViewComponent provides its own test helpers that integrate with RSpec.
# This configuration makes those helpers available in component specs.
#
# Key testing methods available in component specs:
#
# - render_inline(component) - Renders a component and returns the result
# - rendered_component - The HTML output of the last rendered component
# - page - Capybara page object for assertions (requires Capybara)
#
# Example component spec:
#
#   RSpec.describe ButtonComponent, type: :component do
#     it "renders a button with the given label" do
#       render_inline(ButtonComponent.new(label: "Click me"))
#
#       expect(page).to have_button("Click me")
#     end
#
#     it "applies the variant class" do
#       render_inline(ButtonComponent.new(label: "Submit", variant: :primary))
#
#       expect(page).to have_css("button.btn-primary")
#     end
#   end
#
# See: https://viewcomponent.org/guide/testing.html

require "view_component/test_helpers"

RSpec.configure do |config|
  # Include ViewComponent test helpers in component specs
  config.include ViewComponent::TestHelpers, type: :component

  # Include Capybara matchers for component specs (already available via rails_helper)
  config.include Capybara::RSpecMatchers, type: :component
end
