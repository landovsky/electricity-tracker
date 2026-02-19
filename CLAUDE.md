# Agent Instructions

## Artifacts Registry

This project maintains a registry of documentation artifacts at **`artifacts/registry.json`**.

### How to Use the Registry

**ALWAYS check `artifacts/registry.json` when:**
- Starting work on a new feature or bug fix
- Working with unfamiliar parts of the codebase
- Debugging code issues
- Writing or modifying code (frontend, backend, database, tests)
- Making architectural decisions

### Registry Structure

Each artifact entry contains:
```json
{
  "filename": "path/to/artifact.md",
  "description": "Brief description of what the artifact covers",
  "usage": "always" | "decide"
}
```

**Usage field:**
- **`always`** - Must be read before any work (e.g., project overview, core conventions)
- **`decide`** - Read when the artifact is relevant to your current task (e.g., testing conventions when writing tests, API patterns when building endpoints)

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
