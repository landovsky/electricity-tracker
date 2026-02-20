# Per-Property Tracking Mode Implementation Status

**Branch:** `feature/meter-only-tracking` (1 commit: `4801798`)
**Base:** `main-rails` at `558bffd`
**Beads:** workspace-u00 (closed), workspace-in4 (in_progress), workspace-4xe (open, blocked by u00)

## Use Case

Co-op gas boiler: someone reads the gas meter monthly, reports to gas company, logs for year-over-year comparison. No visitors, no stays, no allocation — just a meter log with trend statistics.

## What's Done (Chunk 1: Data Layer) ✓

- **Migration** `20260220195131_add_tracking_mode_to_properties.rb` — adds `tracking_mode` string column, default `"visitors"`, not null
- **Property model** — `enum :tracking_mode, { visitors: "visitors", meter_only: "meter_only" }` — provides `property.visitors?` / `property.meter_only?`
- **MeterReadingEvent model** — added `periodic` to `event_type` enum (alongside `check_in`, `check_out`, `initial`)
- **RecordMeterReading service** (`app/services/record_meter_reading.rb`) — creates a `periodic` MeterReadingEvent with MeterReadings, no Stay. Validates: meter_only property, at least one reading, chronological consistency, monotonic readings
- **Guards** — `CheckInVisitor` and `CheckOutVisitor` reject `meter_only` properties (`validate :validate_visitors_tracking_mode`). `RecordMeterReading` rejects `visitors` properties.
- **Properties controller** — permits `tracking_mode` param
- **Property form** — tracking_mode select dropdown with hint text
- **Property show** — displays tracking mode
- **Locale strings** — Czech translations for all new service errors, enum values, form hints

## What's Done (Chunk 2: Dashboard UI) — Partially

- **PeriodicReadingFormComponent** (`app/components/dashboard/periodic_reading_form_component.rb` + `.html.erb`) — standalone form: date/time, meter fields, note, camera AI button, submit. Posts to `periodic_readings_path`.
- **PeriodicReadingsController** (`app/controllers/periodic_readings_controller.rb`) — handles form submission, calls `RecordMeterReading`, flash messages, turbo stream support
- **Route** — `POST /odecty-mericu` → `periodic_readings#create`
- **Locale strings** — form labels, success message

### NOT yet done in Chunk 2:

- **Dashboard view (`app/views/dashboard/index.html.erb`)** — needs conditional: if `@property.meter_only?`, render `PeriodicReadingFormComponent` instead of `ActionFormsComponent`, and render `HouseStatusComponent` without the visitors section (or a simpler variant showing only meter readings)
- **Dashboard controller** — for `meter_only` properties, skip loading visitors/stays data (not needed, would error or return empty)
- **HouseStatusComponent** — for `meter_only` properties, hide "Who's here" section, show only meter readings
- **RecentActivityComponent** — for `meter_only` properties, `periodic` events should display without visitor name (currently assumes check_in/check_out with a visitor)
- **Readings history** — hide visitor column for `meter_only` properties
- **Turbo stream response** for `PeriodicReadingsController` — needs a `create.turbo_stream.erb` template

## What's Not Started (Chunk 3: Consumption Trends Report)

**Beads:** workspace-4xe (open)

- **CalculateConsumptionTrends service** — takes property + date range, returns monthly consumption deltas from consecutive readings
- **Report view** — for `meter_only` properties: monthly consumption table, year-over-year comparison (e.g. Jan 2025 vs Jan 2026)
- **ConsumptionReportsController** — conditional: if property is `meter_only`, use trends service instead of allocation service

## Key Files Changed

```
# New files
app/services/record_meter_reading.rb
app/controllers/periodic_readings_controller.rb
app/components/dashboard/periodic_reading_form_component.rb
app/components/dashboard/periodic_reading_form_component.html.erb
db/migrate/20260220195131_add_tracking_mode_to_properties.rb

# Modified files
app/models/property.rb                    (enum added)
app/models/meter_reading_event.rb         (periodic event_type)
app/services/check_in_visitor.rb          (guard added)
app/services/check_out_visitor.rb         (guard added)
app/controllers/properties_controller.rb  (permit tracking_mode)
app/views/properties/_form.html.erb       (tracking_mode select)
app/views/properties/show.html.erb        (show tracking_mode)
config/locales/cs.yml                     (new translations)
config/routes.rb                          (periodic_readings route)
db/schema.rb                              (tracking_mode column)
```

## Smoke Test Results (all passed in rails runner)

1. Record a periodic reading on meter_only property → creates event with type `periodic`
2. Monotonic violation → rejected with Czech error message
3. CheckInVisitor on meter_only property → rejected
4. RecordMeterReading on visitors property → rejected
