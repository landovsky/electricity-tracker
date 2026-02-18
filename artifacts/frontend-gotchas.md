# Frontend Gotchas

Known pitfalls and patterns for front-end work in this project.

## Flash Messages & Toasts

### Toast rendering on full page loads vs Turbo Streams

Flash messages are rendered as toasts in two places:

1. **Layout** (`app/views/layouts/application.html.erb`) — renders `flash.each` inside `#toast-container` on full page loads (redirects). This **consumes** the flash.
2. **Turbo Stream responses** (e.g., `stays/create.turbo_stream.erb`) — append to `#toast-container` using `flash.now` values.

**Gotcha:** If you set a flash via `redirect_to ..., notice:` but the target page doesn't render it, the flash persists in the session. It will then appear unexpectedly on the next Turbo Stream response that iterates `flash.each`. Always ensure full-page-load flash messages are consumed in the layout.

### flash vs flash.now

- Use `flash[:notice]` with `redirect_to` (survives the redirect)
- Use `flash.now[:notice]` with Turbo Stream responses (consumed immediately, not persisted)

## HTML5 Form Validations

### ValidationHelper pattern

Use `ValidationHelper` (`app/helpers/validation_helper.rb`) to add HTML5 `required` attributes with localized custom error messages:

```erb
<%= number_field_tag :main_meter_reading, nil, **number_validation %>
<%= select_tag :visitor_id, options, **select_validation %>
<%= form.text_field :name, **field_validation %>
<%= form.email_field :email, **email_validation %>
```

Available helpers: `field_validation`, `select_validation`, `number_validation`, `email_validation`, `generic_field_validation`.

Each sets `oninvalid`, `onvalid`, `oninput` handlers to show localized custom messages and adds `required: true`.

**Gotcha:** The `prompt:` option on `select_tag` creates an option with empty value, which works with `required` to prevent submission. But `include_blank:` on `form.select` may behave differently — test carefully.

### Where required is used

- Dashboard forms: visitor select, main meter reading, consumption kWh, note (manual entry)
- CRUD forms: visitor name, user name/email, property name
- Login forms: email, phone, OTP code (hardcoded `required` attributes)
- Onboarding: name (hardcoded `required`)

## Active Interaction Error Translation

### The `missing` error key

ActiveInteraction raises `missing` errors (not `blank`) when required inputs are nil. The translation key path is:

```
cs.active_interaction.errors.models.<service_name>.attributes.<field>.missing
cs.active_interaction.errors.messages.missing
```

A generic fallback is defined in `config/locales/cs.yml` at `cs.active_interaction.errors.messages.missing`. Add model-specific overrides under `cs.active_interaction.errors.models.*` if needed.

### ActiveInteraction vs ActiveRecord errors

- ActiveInteraction uses `missing` for nil required inputs
- ActiveRecord uses `blank` for presence validations
- Both need separate translation entries

## Turbo Streams & Stimulus

### Forms inside turbo-frames with turbo_stream responses

Forms inside `<turbo-frame>` elements trigger frame-scoped navigation by default. If the server responds with `turbo_stream` format, both the stream actions AND frame navigation may execute, causing duplicate rendering (e.g., the form appears twice).

**Fix:** Add `data: { turbo_frame: "_top" }` to forms that expect turbo_stream responses. This tells frame navigation to target the full page (which is harmless since the turbo_stream response handles all updates). The streams still process normally.

```erb
<%= form_with url: stays_path, data: { turbo_frame: "_top" } do |f| %>
```

### Preserving Stimulus targets in Turbo Stream replacements

When replacing a `<turbo-frame>` via `turbo_stream.replace`, ensure the replacement HTML includes the same `data-*-target` attributes. Stimulus controllers bound to the parent won't re-discover targets in new DOM unless the controller reconnects.

### Toast auto-dismiss

Toasts use `toast_controller.js` with a default 3000ms duration. They fade in on `connect()` and auto-remove from DOM after fade-out. No cleanup needed — each toast manages its own lifecycle.

## Form Styling

### Error field styling

CRUD forms (`visitors/_form`, `users/_form`, `properties/_form`) display validation errors as a red box above the form using `model.errors.each`. There is no field-level error highlighting via a forms initializer — errors are only shown in the summary box.

Dashboard forms (check-in, check-out, manual entry) show errors via flash toasts, not inline.

### CSS classes

Forms use Tailwind utility classes directly. There's no shared form component or builder. Common patterns:
- Input: `w-full border border-gray-300 rounded-lg px-3 py-2.5 text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500`
- Label: `block text-sm font-medium text-gray-700 mb-1`
- Required indicator: `<span class="text-red-500">*</span>`
- Optional indicator: `<span class="text-gray-400">(nepovinné)</span>`
