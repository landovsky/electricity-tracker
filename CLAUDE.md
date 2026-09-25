# Agent Instructions

## Artifacts

Read **always** artifacts before any work. Read **decide** artifacts when relevant to your current task.

### Always read
- `artifacts/01-system-builder-instructions.md` — Build cycle, completeness rules, testing philosophy, commit discipline, multi-agent coordination
- `artifacts/02-technical-requirements.md` — Stack (Rails 8 + SQLite + Tailwind + Stimulus), key gems, auth, testing tools, deployment model

### Read when relevant
- `artifacts/specification/electricity-tracker-spec.md` — Product spec: domain model, use cases, allocation algorithm, edge cases, UI designs, roles
- `artifacts/specification/00-spec-philosophy-how-to-keep-it-up-to-date.md` — Spec maintenance rules and update workflow
- `prototype/index.html` — Clickable HTML prototype of all end-user screens. Serve via `python3 -m http.server 8080` from prototype/
- `artifacts/00-project-initiation-guide.md` — One-time bootstrap guide (only if project hasn't been initialized)
- `artifacts/03-tooling-for-efficiency.md` — Policy for developer automation (Rule of Three, naming, budgets)
- `artifacts/team-structure.md` — Team roles (Lead, Developer, QA) and expected behaviors
- `artifacts/deployment-notes.md` — Deployment infrastructure, Tailwind Docker gotcha, bootstrap task, resolved issues
- `artifacts/gitops.md` — K3s/Flux release flow, CI/CD pipeline, K8s resources, secrets, environment variables
- `artifacts/frontend-gotchas.md` — Flash/toast rendering, form validation, Stimulus + Turbo patterns

## Debug Endpoints (development only)

**Consumption report debug JSON**: `GET /consumption_reports.json`

Use this to inspect the allocation algorithm output, period breakdown, and raw data when debugging consumption report issues. No auth required in development.

Query params (same as HTML report):
- `?year=2025` — specific year
- `?year=all` — all time
- `?start_date=2025-01-01&end_date=2025-06-30` — custom range
- (no params) — current year

Response includes: `date_range`, `report` (per-visitor breakdown), `periods` (with present_visitors, manual_entries, total_kwh), `meter_reading_events` (all events with readings), `stays`, `manual_consumption_entries`.

Example: `curl -s http://localhost:3333/consumption_reports.json?year=2026 | python3 -m json.tool`

## Completeness Rules

**No placeholders.** Every committed handler, controller, or service must contain real logic — not stubs that log and return. If you can't implement something fully, flag it as blocked. Do not ship code that looks done but does nothing.

**When reporting task completion**, always state:
- What is **functional** (wired, tested, works end-to-end).
- What is **stubbed or incomplete** (and why).
- What is **blocked** (and on what).

"Tests pass" alone is not a quality signal. Tests can pass around empty code.

**Test the orchestration layer.** If handlers wire services together, test through the handler — not just the individual services in isolation. Testing leaves without testing the tree proves nothing about whether the system works.

## Team Coordination

- Workers use **feature branches**, not the main branch. Lead merges after review.
- Lead must **read key deliverable files** before merge — not just check test counts.
- Tasks should be **vertically sliced** (one feature end-to-end) rather than horizontally sliced (all handlers in one task, all services in another). Splitting a service from its caller across workers invites placeholders.
- After each merge round, the lead runs a **gap check** against the spec. This is a required step, not an afterthought.
