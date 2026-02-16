# ViewComponents

This directory contains all ViewComponent classes for the Family House Electricity Tracker.

## What are ViewComponents?

ViewComponents are a framework for building reusable, testable, and encapsulated view components in Rails. They provide:

- **Testability**: Components can be unit-tested in isolation without rendering full views
- **Encapsulation**: Each component is a Ruby class with its own template
- **Performance**: ~10x faster than partials (compiled Ruby vs. re-parsed ERB)
- **Type Safety**: Initialize parameters are validated by Ruby

## Directory Structure

```
app/components/
├── application_component.rb       # Base class for all components
├── button_component.rb            # Example: Button component class
└── button_component.html.erb      # Example: Button component template
```

## Creating a Component

Use the Rails generator (recommended):

```bash
# Note: Generator may require fixing DATABASE_URL environment variable
# Alternatively, create files manually following the pattern below
bundle exec rails generate component Button label variant:string
```

Or create manually:

**app/components/button_component.rb**
```ruby
# frozen_string_literal: true

class ButtonComponent < ApplicationComponent
  def initialize(label:, variant: :primary)
    @label = label
    @variant = variant
  end

  def css_classes
    base = "btn"
    "#{base} btn-#{@variant}"
  end
end
```

**app/components/button_component.html.erb**
```erb
<button class="<%= css_classes %>">
  <%= @label %>
</button>
```

## Using Components in Views

Render components using the `render` helper:

```erb
<%= render ButtonComponent.new(label: "Save", variant: :primary) %>
<%= render ButtonComponent.new(label: "Cancel", variant: :secondary) %>
```

## Testing Components

Component specs live in `spec/components/` and use ViewComponent's test helpers:

**spec/components/button_component_spec.rb**
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ButtonComponent, type: :component do
  it "renders the label" do
    render_inline(described_class.new(label: "Click me"))

    expect(page).to have_button("Click me")
  end

  it "applies the variant CSS class" do
    render_inline(described_class.new(label: "Submit", variant: :success))

    expect(page).to have_css("button.btn-success")
  end

  it "defaults to primary variant" do
    render_inline(described_class.new(label: "Default"))

    expect(page).to have_css("button.btn-primary")
  end
end
```

## Best Practices

### 1. Keep Components Focused
Each component should do one thing well. If a component has too many responsibilities, split it.

### 2. Use Slots for Composition
ViewComponent supports slots for flexible layouts:

```ruby
class CardComponent < ApplicationComponent
  renders_one :header
  renders_one :body
  renders_many :actions
end
```

### 3. Document Component APIs
Add clear documentation to component classes explaining:
- Required vs. optional parameters
- Valid values for parameters
- Examples of usage

### 4. Test the Public Interface
Test what the component renders, not internal implementation details.

### 5. Follow Naming Conventions
- Component classes: `FooComponent` (singular, ends with `Component`)
- Component files: `foo_component.rb` and `foo_component.html.erb`
- Component specs: `foo_component_spec.rb`

## Resources

- [ViewComponent Documentation](https://viewcomponent.org/)
- [ViewComponent Guide](https://viewcomponent.org/guide/)
- [ViewComponent Testing](https://viewcomponent.org/guide/testing.html)
- [ViewComponent Slots](https://viewcomponent.org/guide/slots.html)
