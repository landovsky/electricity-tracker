# Family House Electricity Tracker — System Specification

**Version:** 0.5
**Last updated:** 2026-02-16

---

## 1. Overview

A web application for tracking and fairly splitting electricity consumption among family members (Visitors) who use a shared family house. The house has a main electricity meter and a secondary meter for the upper floor. Visitors check in and out with meter readings, and the system calculates each visitor's share of consumption in kWh.

---

## 2. Glossary

| Term | Definition |
|------|-----------|
| **Property** | The family house. Single property for now, modeled as entity for future extensibility. |
| **Meter** | A physical electricity meter. Type: `main` or `secondary`. Readings are cumulative kWh, monotonically non-decreasing. |
| **Visitor** | A payer identity (may represent a family). Not a user account. Has a name and active/archived status. |
| **User** | A person who operates the app. Role: `admin` or `member`. |
| **Stay** | A visitor's presence at the property. Has check-in and (optionally) check-out events. Status: `open` or `closed`. |
| **Meter Reading Event** | A timestamped set of meter readings tied to a stay transition (check-in or check-out). |
| **Manual Consumption Entry** | A direct kWh attribution to a visitor without a formal stay (e.g., EV charging). |
| **Period** | A computed (not stored) time interval between two consecutive meter reading events. |

---

## 3. Use Cases

### UC1: Visitor Check-in

A visitor arrives, reads both meters (main + secondary), and records the readings with a timestamp. The system validates readings are ≥ previous readings.

**Preconditions:** Visitor exists in the system. Visitor does not have an open stay.
**Postconditions:** An open stay is created. Meter reading event is recorded.

### UC2: Visitor Check-out

A visitor departs, reads both meters, records readings. The system closes the stay.

**Preconditions:** Visitor has an open stay.
**Postconditions:** Stay is closed. Meter reading event is recorded. Consumption for completed periods can now be calculated.

### UC3: Manual Consumption Entry

A visitor enters a direct kWh amount attributed to themselves without a formal stay (e.g., Tom charges EV, reads 15 kWh from car records).

**Preconditions:** Visitor exists.
**Postconditions:** Entry is recorded. Amount is directly attributed to the visitor and deducted from the shared pool for the enclosing period.

### UC4: Admin Correction

An admin edits or deletes a bad meter reading, corrects a stay's timestamps, or adjusts a manual entry. The system recalculates affected periods.

**Preconditions:** User has admin role.
**Postconditions:** Record is corrected. Audit trail is updated. Derived reports reflect the correction.

### UC5: Consumption Report

View a breakdown of each visitor's attributed consumption (in kWh) for a given date range (typically annual).

**Preconditions:** At least one completed period exists.
**Output:** Per-visitor total kWh, broken down by: period shares, manual entries, empty-house share.

---

## 4. Edge Cases

| ID | Scenario | Resolution |
|----|----------|------------|
| E1 | Multiple overlapping stays (3+ visitors) | Consumption split equally N ways for that period |
| E2 | Empty-house periods (no open stays) | Accumulated as unattributed, split equally among all visitors in the billing period |
| E3 | Same-day check-in and check-out | Supported. May result in 0 kWh delta — that's fine |
| E4 | Manual entry during empty house | Attributed directly to visitor, deducted from empty-house shared pool |
| E5 | Manual entry during active stay | Attributed directly, deducted from shared pool for that period |
| E6 | Meter reading goes down | Validation error. Admin can correct if someone entered wrong number |
| E7 | Forgotten reading at check-in | System requires it. Admin can backfill |
| E8 | Secondary meter not read | Optional — defaults to previous reading (implying 0 upper-floor consumption) |
| E9 | Multiple *different* visitors check in without intervening check-outs | Allowed — visitors overlap. Stays tracked independently. (A single visitor cannot have two open stays — see C2.) |
| E10 | One-off / unregistered guest | The accompanying visitor creates a new visitor record for the guest, checks them in separately. Guest can be archived after departure. (Members can create visitors — see Roles.) |
| E11 | Concurrent check-in and check-out (visitor swap) | Single meter reading serves both events |

### Partial Overlap Example

Visitor A stays Jan 2–3, Visitor B stays Jan 3–10. Meter readings taken at each check-in/check-out create this timeline:

```
Jan 2 (A checks in)  ──→  Jan 3 (A out + B in)  ──→  Jan 10 (B checks out)
       Period 1: A alone            Period 2: B alone
```

- **Period 1 (Jan 2–3):** Only A has an open stay → 100% attributed to A.
- **If A checks out and B checks in simultaneously on Jan 3rd**, a single meter reading serves both events (E10). No overlap period exists.
- **If they truly overlap** (B checks in Jan 3rd morning, A checks out Jan 3rd evening), the period between those two events is split equally between A and B.
- **If there is a gap** (A checks out morning, B checks in evening with a new reading), a brief empty-house period exists between them.

**Key principle:** Presence is determined by open stays. Periods are bounded by meter reading events.

---

## 5. Domain Model & Relationships

```
Property 1──* Meter
Property 1──* Stay
Visitor   1──* Stay
Visitor   1──* ManualConsumptionEntry
Stay      1──1 CheckInEvent (MeterReadingEvent)
Stay      1──0..1 CheckOutEvent (MeterReadingEvent)
MeterReadingEvent 1──* MeterReading (one per meter)
```

### Entity Details

#### Property
- `id`
- `name`
- `address` (optional)

#### Meter
- `id`
- `property_id` (FK)
- `meter_type` — enum: `main`, `secondary`
- `label` — human-readable name (e.g., "Main meter", "Upper floor")
- `unit` — always `kWh` for now

#### Visitor
- `id`
- `name`
- `status` — enum: `active`, `archived`
- `note` (optional)

#### User
- `id`
- `email`
- `name`
- `role` — enum: `admin`, `member`

#### Stay
- `id`
- `visitor_id` (FK)
- `property_id` (FK)
- `check_in_event_id` (FK → MeterReadingEvent)
- `check_out_event_id` (FK → MeterReadingEvent, nullable)
- `status` — derived: `open` (no check-out) or `closed`
- `note` (optional)

#### MeterReadingEvent
- `id`
- `recorded_at` — timestamp of when the reading was taken
- `recorded_by_user_id` (FK → User)
- `event_type` — enum: `check_in`, `check_out`
- `note` (optional)

#### MeterReading
- `id`
- `meter_reading_event_id` (FK)
- `meter_id` (FK)
- `value_kwh` — decimal, the cumulative meter reading

#### ManualConsumptionEntry
- `id`
- `visitor_id` (FK)
- `property_id` (FK)
- `date` — the date the consumption occurred
- `kwh` — decimal, positive
- `note` — description (e.g., "EV charging")
- `recorded_by_user_id` (FK → User)

---

## 6. Constraints

| # | Constraint | Enforcement |
|---|-----------|-------------|
| C1 | Meter readings are monotonically non-decreasing | Validation; admin override |
| C2 | A visitor can have at most one open stay at a time | Validation |
| C3 | Check-out reading ≥ check-in reading (per meter) | Validation |
| C4 | Main meter reading is required on every event | Validation |
| C5 | Secondary meter reading is optional (defaults to last known value) | Application logic |
| C6 | Event timestamps must be chronologically consistent with prior events | Validation; admin override |
| C7 | Manual entries must have positive kWh values | Validation |
| C8 | Manual entry kWh should not exceed unattributed consumption in the enclosing period | Warning (soft validation) |

---

## 7. Allocation Algorithm (v1: Equal Split)

The allocation is **computed, not stored**, and can be recalculated at any time.

### Step 1: Build the Timeline

Collect all MeterReadingEvents, sorted by `recorded_at`. Each consecutive pair defines a **Period**.

### Step 2: Analyze Each Period

For each period, determine:

- `total_kwh` = main meter delta between bounding events
- `upper_floor_kwh` = secondary meter delta (tracked but unused in v1)
- `present_visitors` = visitors with open stays during this period
- `manual_kwh` = sum of ManualConsumptionEntries falling within this period, grouped by visitor

### Step 3: Allocate Each Period

```
shared_kwh = total_kwh - sum(all manual_kwh in this period)

if present_visitors is NOT empty:
    each present visitor gets: shared_kwh / count(present_visitors)
else:
    this is empty-house consumption → add to unattributed_pool
```

Each visitor's `manual_kwh` is added directly to their total.

### Step 4: Distribute Empty-House Consumption

`unattributed_pool` is split equally among all visitors who had **at least one stay** in the reporting period.

### Step 5: Final Per-Visitor Total

```
visitor_total = sum(period_shares) + sum(manual_entries) + empty_house_share
```

---

## 8. Audit & Data Integrity

- All records are **soft-deletable** (`deleted_at` timestamp).
- All edits to meter readings, stays, and manual entries are logged in an **audit trail** (who changed what, when, previous value).
- Reports are always **derived from current data** — never cached as source of truth. Recalculation is idempotent.

---

## 9. Roles & Permissions

| Action | Member | Admin |
|--------|--------|-------|
| Record check-in / check-out | ✅ | ✅ |
| Create manual consumption entry | ✅ | ✅ |
| View consumption report | ✅ | ✅ |
| Create visitors | ✅ | ✅ |
| Archive visitors | ❌ | ✅ |
| Edit / delete any record | ❌ | ✅ |
| Override validation constraints | ❌ | ✅ |
| Manage users | ❌ | ✅ |

**Admin interface:** Admin functions (corrections, visitor management, user management, validation overrides) are handled via JSON API endpoints and Rails console. No admin UI is built in v1.

---

## 10. Screens

The app is designed for occasional use (a few times per month) on mobile devices at the property. Most interactions should complete without navigating away from the main screen.

### S1: Main Screen (Dashboard + Actions)

The single screen users spend 95% of their time on. Combines status overview with inline action forms.

**Top section — House Status:**
- **Who's here now** — visitor names with check-in dates, each with a "Check Out" button/link right next to them
- **Current meter readings** — last recorded main and secondary values with date

**Middle section — Action Area:**

A single expandable/collapsible area (or tab bar) with three modes:

**Check In**
- Visitor picker (only visitors without open stays, plus a "New visitor" option for one-off guests), date/time (defaults to now), main meter reading (required), secondary reading (optional), note. Last known readings shown as reference.

**Check Out**
- Visitor picker (only visitors with open stays — pre-selected if only one), date/time (defaults to now), main meter reading (required), secondary reading (optional), note. Last known readings shown as reference.

**Log Consumption**
- Visitor picker (all active visitors), date (defaults to today), kWh amount, note (required).

Each mode is a compact inline form — 2–4 fields, one submit button. On success: form resets, status section updates, a brief confirmation appears. No page navigation.

The default mode is context-aware:
- If nobody is checked in → defaults to Check In
- If someone is checked in → defaults to Check Out
- Manual entry is always available but not the default

**Bottom section — Recent Activity:**
- Last 5 events (check-ins, check-outs, manual entries) as a compact list. Tapping an entry expands to show details. Link to full history.

### S2: Consumption Report

Separate screen — this is a different context (settlement review, not data entry).

**Controls:**
- Date range — preset options: "This year", "Last year", custom range

**Display:**
- **Summary table** — one row per visitor:
  - Visitor name
  - Shared consumption (kWh)
  - Manual entries (kWh)
  - Empty-house share (kWh)
  - **Total (kWh)**
- **Totals row** — should equal the main meter delta for the period (sanity check)
- **Timeline visualization** (nice-to-have) — stays and readings over time

### S3: Readings History

Chronological log of all meter reading events and manual entries.

- Date, event type, visitor name, meter values (or kWh for manual), recorded by
- Filterable by visitor and date range

The digital equivalent of the current paper notebook. Reachable from "Recent Activity" on the main screen.

### Screen Map

```
Main Screen (S1)  ──→  Consumption Report (S2)
       │
       └──────────→  Readings History (S3)
```

Three screens. The main screen handles all day-to-day operations inline. Report and history are reference views.

### Design Principles

- **Mobile-first** — most readings happen on-site, phone in hand
- **One-screen workflow** — check-in/check-out completes without navigation
- **Big tap targets** — meter readings are entered standing next to the meter
- **Show reference values** — always display the last known reading so the user can sanity-check their input
- **Context-aware defaults** — the form pre-selects the most likely action and visitor
- **Forgiving** — soft warnings over hard blocks where possible; admin can fix mistakes later

## 11. Extension Points (Designed For, Not Built)

| Extension | Notes |
|-----------|-------|
| **Weighted / custom split strategies** | Period allocation logic is isolated. Alternative strategies (upper floor attributed to specific visitor, time-weighted, etc.) can replace equal split. |
| **Cost calculation** | Apply CZK/kWh rate to final kWh totals. Rates may vary (tiered, seasonal). Separate concern layered on allocation. |
| **Photo meter readings** | MeterReadingEvent gets optional image attachment. AI extraction populates reading value for user confirmation. |
| **Multi-property** | Property is already a first-class entity. |
| **Visitor self-service** | Visitors could get accounts and record their own check-ins. |

---

## 12. Open Questions

- [ ] Should stays optionally track which floor a visitor occupies? (Enables future upper-floor attribution via secondary meter. Simple checkbox on check-in, not inferred from readings.)

### Resolved

- ~~Recurring visitors / templates~~ — Not needed.
- ~~Negative manual entries~~ — No. Corrections handled by editing records and recalculating.
- ~~Scale~~ — Very low, under 100 visits/year. No pagination needed.
- ~~Room/floor tracking via secondary meter readings~~ — Rejected. Meter readings reflect consumption during a period, not who consumed it. Future attribution should use an explicit flag on the stay, not inference from who recorded the reading.
- ~~Multiple open stays per visitor for one-off guests~~ — Rejected. Instead, members can create a new visitor record for the guest (E10).
