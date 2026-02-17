# System Tests

This directory contains end-to-end system tests that verify complete user workflows through the browser interface.

## Running System Tests

### With JavaScript (Headless Chrome)

```bash
bundle exec rspec spec/system
```

This requires Chrome and compatible chromedriver to be installed. The tests will run in headless mode.

### Without JavaScript (Rack Test - Fallback)

If Chrome is not available (e.g., in minimal CI environments), set:

```bash
CAPYBARA_DRIVER=rack_test bundle exec rspec spec/system
```

Note: Rack test cannot execute JavaScript, so Turbo Stream interactions will not be tested. This mode is useful for basic smoke tests and CI environments without browser support.

## Test Structure

System tests are organized by user flow:

- `check_in_flows_spec.rb` - Visitor check-in scenarios (UC1)
- `check_out_flows_spec.rb` - Visitor check-out scenarios (UC2)
- `manual_entry_flows_spec.rb` - Manual consumption entry flows (UC3)
- `consumption_report_flows_spec.rb` - Report generation (UC5)
- `readings_history_flows_spec.rb` - Readings history viewing

## Test Helpers

The `SystemHelpers` module (in `spec/support/system_helpers.rb`) provides:

- `perform_check_in` - Fill and submit check-in form
- `perform_check_out` - Fill and submit check-out form
- `create_manual_entry` - Create manual consumption entry
- `expect_flash` - Verify flash messages
- `verify_stay_exists` - Check database state for stays
- `verify_meter_readings` - Check meter readings were created correctly
- `build_timeline` - Create complex test scenarios with multiple stays

## Verification Strategy

Each test verifies **two layers**:

1. **UI State** - What the user sees (flash messages, page content, form updates)
2. **Database State** - What actually happened (records created, correct values, relationships)

This dual verification ensures the full stack works correctly, not just individual components.

## Chrome/Chromedriver Compatibility

If you encounter chromedriver errors:

1. **Check Chrome is installed:**
   ```bash
   google-chrome --version
   ```

2. **Update webdrivers (if using webdrivers gem):**
   ```bash
   bundle update webdrivers
   ```

3. **Or manually download matching chromedriver** from:
   https://chromedriver.chromium.org/downloads

4. **Architecture issues** (ARM/x86):
   Some environments may not support the chromedriver binary. Use `CAPYBARA_DRIVER=rack_test` as fallback.

## CI/CD Notes

For CI environments (GitHub Actions, GitLab CI, etc.):

- Include Chrome installation in CI setup
- Use headless mode (default)
- Consider using `selenium/standalone-chrome` Docker image
- Or use rack_test for basic smoke tests (no JS)
