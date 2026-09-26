# Vyúčtování elektřiny Suchá 2025/26 (manual settlement)

The app wasn't used this year (bugs), so stays were recorded in the paper notebook.
This folder holds everything needed to recompute the settlement without re-OCRing.

Billing period 27.08.2025 – 28.08.2026, PPAS invoice 1126407855, 13 904,22 Kč incl. VAT.

## Files

| Path | What |
|---|---|
| `events.csv` | **Canonical data.** One row per visitor action (check_in / check_out / manual_kwh / reading) with local time, readings, `source` (notebook / app / invoice / estimate / assumed) and `status` (`pending` = not yet confirmed). Merges the notebook with stays only recorded in the app. Drives both the settlement and the app import. |
| `readings.csv` | Earlier notebook-only transcription (superseded by events.csv, kept for provenance). Every notebook row: date, who, P/O, VT/NT/garage readings as used, the value *as written*, and notes on corrections. `present_after` = who is in the house in the interval that starts at that row. |
| `charges.csv` | EV charging kWh (superseded by `manual_kwh` rows in events.csv). |
| `advances.csv` | Advances each branch paid into the shared account for this invoice (date, branch, Kč). |
| `invoice.json` | Invoice facts: start/end readings, fixed vs variable charges, per-MWh unit prices for 2025 and 2026. |
| `calc/settle.py` | Allocation. Reads events.csv + invoice.json, prints JSON (`calc/out.json`). |
| `calc/build.py` + `calc/template.html` + `calc/template-branch.html` | Renders `vyuctovani-sucha-2026.html` (common page, served at `/vyuctovani/sucha/2026`) and `vyuctovani-sucha-2026-{jiri,kristina,petr}.html` (branch pages at `/vyuctovani/sucha/2026/<branch>`: advances balance, share breakdown, members with a toggle that folds fixed + empty-house share into the kWh price) from `out.json`. |
| `sources/` | Original invoice PDF and the three notebook photos (rotated upright). |
| `ocr/` | Four independent transcriptions (Claude, GPT-6 Sol Pro, Gemini 3.1 Pro, Qwen 3.8 Max) and the reconciled verdict with disputed cells. |

Re-run after editing the CSV:

```sh
cd calc && python3 settle.py > out.json && python3 build.py && python3 check.py   # pages land in this folder; check.py reconciles every number shown
```

`settle.py` asserts that the first/last readings in the period equal the invoice readings.

## Allocation rules

- Three payers (family branches), each collecting from its own members: **Jiří**; **Kristina** (Kristina, Edita, Marek); **Petr** (Petr, Tereza, Bára, Johana).
- Fixed charges (9 299,25 Kč) and empty-house consumption split ⅓ per branch.
- Interval consumption between consecutive readings is split equally among the branches present.
- Garage sub-meter is behind the main meter. When Jiří shares the house with another branch, the garage kWh go to him before the split; otherwise they are ordinary consumption of that interval.
- EV charging goes to the charging person's branch.
- Per-member breakdown (for each branch's internal split, direct consumption only): a branch's share of an interval is split equally among its members present; EV charging goes to the person charging; garage kWh go to whoever used Jirka's part (Jirka, or Johana 4.–6.4.2026 per "JOHANA (JIRKA)"). Fixed charges and empty-house share stay at branch level.
- kWh priced with the invoice's 2025 / 2026 unit prices, then scaled (+3.6 %) so the variable part equals the invoice exactly (PPAS estimated a higher 2025 share than the notebook shows).
- Advances (zálohy): `advances.csv` (from the bank export `sources/zalohy-sucha-2026.xls`, 11 × 635 Kč per branch, Oct 2025 – Aug 2026; the September 2025 payment belongs to the previous invoice). Balance per branch = advances − share of the invoice; positive is sent back to the branch from the family's shared account, negative is paid by the branch into it. All three branches pay their monthly advances into that shared account and PPAS is paid from it (the PPAS refund also lands there).

## Known assumptions

- Jirka 24.–26.7.2026 has no readings; check-out at 26.7. uses estimated 86850 / 124662 (by nights; garage 2117 is real).
- Kristina's departure after 17.7.2026 isn't written; assumed 19.7.
- Page 3 NT values `124752?` / `124783?` are swapped digits → 124725 / 124738 (matches invoice end).
- Tereza 17.11.2025 VT 86754 (the app confirms it; the margin note "T 14" is wrong).
- App-only stays: Petr from 5.4., Marek (visitor "djakma@gmail.com") 8.–10.5.; Edita's 18.6. check-in uses the app reading (the notebook's 19.6. row copied an April value). Bára's app check-in (entered 6.4. with Petr's reading) is moved to 5.4.
- Jirka 19.–20.9.2026 (next period): left 20.9. per Tomáš, no readings written — check-out uses his arrival values, so his use falls into the empty-house pool at the next reading.
- 19.–21.9.2025 split equally; the notebook's margin gave Jirka only the garage (17) and Kristina the rest (26).

## Loading into the app (resume tracking)

`bin/rails settlement:import` replays `events.csv` into the app (`lib/settlement_import.rb`):
soft-discards every event / stay / manual entry the app holds inside the log's time window
(reversible), renames visitor "djakma@gmail.com" → "Marek", then replays the rows through
CheckInVisitor / CheckOutVisitor / CreateManualConsumptionEntry, so all app validations run.

```sh
bin/rails db:download && bin/rails db:load     # fresh prod copy into dev (read-only on prod)
bin/rails settlement:import                    # dry run (default)
APPLY=1 bin/rails settlement:import            # write; re-running is a no-op
```

It refuses if the app has live events after the log's last row, or in-window rows created
after the snapshot the log was reconciled against (`CREATED_BEFORE`, default 2026-09-21).

**Applied to production 2026-09-25** (v0.2.9, `kubectl exec … env APPLY=1 bin/rails settlement:import`):
discarded 20 events / 13 stays / 1 manual entry, replayed 50 rows, renamed visitor #15 → Marek;
period total 1125 kWh = meter delta, no open stays. Pre-import backup (undo = restore it):
`/rails/storage/production.sqlite3.bak.pre-settlement-import-20260925` on the PVC, local copy in
`tmp/db/production.bak.pre-settlement-import-20260925.sqlite3`.

The app's own report will not equal the settlement above: it splits per visitor (not per
household), doesn't carve the garage out for Jirka, and spreads empty-house kWh over all visitors.
