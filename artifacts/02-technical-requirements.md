## Technical Requirements

**Stack:** Rails 8, SQLite, Tailwind CSS, ERB, ViewComponents, Stimulus, Propshaft

**Architecture:**
- Slim controllers and models — business logic lives in service objects (`app/services/`) using `active_interaction`
- ViewComponents for all reusable UI (`app/components/`)
- Stimulus controllers for interactivity (`app/javascript/controllers/`)
- JS utility classes for shared functions (`app/javascript/utils/`) — extract during refactoring, not upfront
- No background jobs — all operations are synchronous
- No passwords — email-based magic link authentication (hand-rolled, ~2 controllers)

**Key gems:**
- `discard` — soft deletes via `deleted_at`
- `audited` — audit trail for meter readings, stays, manual entries
- `nilify_blanks` — normalize empty strings to nil
- `active_interaction` — service object convention (inputs, validations, composition)
- `stimulus-rails` + `turbo-rails` — SPA-like interactions (inline forms on dashboard)
- `view_component` — encapsulated, testable UI components

**Auth:**
- Hand-rolled magic link authentication (no Devise, no passwords)
- User submits email → receives link with signed token → clicking link creates session
- `letter_opener` / `letter_opener_web` for magic link emails in development

**Database:**
- SQLite (single-file, no external dependencies)
- Soft deletes (`deleted_at`) on all domain models via discard
- Audit trail via audited for edits to meter readings, stays, manual entries

**Testing:**
- `rspec-rails`, `factory_bot_rails`, `ffaker`, `shoulda-matchers`
- `capybara`, `selenium-webdriver` for system tests
- `database_cleaner`
- Service objects (active_interactions) are the primary unit test target
- Allocation algorithm needs thorough edge-case coverage

**Code quality:**
- `rubocop` + `rubocop-rails` + `rubocop-performance`
- `pry-rails` for console debugging

**Deployment:**
- Single-server, single-process
- No external dependencies (no Redis, no Postgres)
