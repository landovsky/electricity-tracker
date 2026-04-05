# Match Meter Reading

You are extracting utility meter readings from OCR text.
The meter may be an electricity, gas, or water meter.

## Context

The property has these meters:
%{meters_json}

Each meter entry: { id, label, identifier, meter_type, meter_group, unit, last_reading_kwh }

Meters with the same `identifier` are physically on the same device (e.g. a dual-tariff electricity meter showing both VT and NT readings on one display).

The `identifier` field is the physical serial number or label printed on the meter device. If the OCR text contains a serial number or device identifier, use it to match to the correct meter.

## Task

1. Find ALL meter reading values in the OCR text
2. Match each to the most likely meter from the list
3. Use the last known readings as reference — the new reading should be
   >= the last reading (meters are cumulative, monotonically increasing)
4. For electricity meters: NT = low tariff (night), VT = high tariff (day) —
   if the OCR text or context suggests a tariff type, match accordingly
5. For gas meters: readings are in m³
6. For water meters: readings are in m³ or litres
7. A single image may show MULTIPLE readings (e.g. a dual-tariff meter
   with VT and NT displays). Return ALL readings you can identify.
8. If the image shows only one reading, return a single-element array.
9. Only return actual meter readings. Ignore serial numbers, barcodes,
   model numbers, year stamps, and other non-reading numbers.
10. If a number is wildly inconsistent with ALL last known readings
    (e.g. 100x larger), it is almost certainly NOT a meter reading —
    do NOT include it.

## Dual-Tariff Meter OCR Artifacts (CRITICAL)

Czech dual-tariff electricity meters label their displays with Roman
numerals: **I** for tariff 1 (VT) and **II** for tariff 2 (NT).

OCR often merges these Roman numeral prefixes with the digits:
- `10868207` → the leading `1` is actually `I` (Roman numeral) → real digits are `0868207`
- `111243230` → the leading `11` is actually `II` (Roman numeral) → real digits are `1243230`

**When you see two large numbers where one starts with `1` and the other
with `11`, check if stripping those prefixes produces values consistent
with the last known readings.** If so, strip the prefix.

## Decimal Point Rule (CRITICAL)

Meter displays often show readings with **1 decimal place** — the last
digit on the display is tenths of the unit. OCR often loses the decimal point.

**You MUST insert a decimal point before the last digit of the main reading.**

Examples:
- OCR reads `0089602` → actual reading is `8960.2`
- OCR reads `0097530` → actual reading is `9753.0`
- OCR reads `123456` → actual reading is `12345.6`

Use the last known reading to sanity-check: the new reading should be
slightly higher than the last. If your result is ~10x the last reading,
you probably forgot the decimal point.

## Input

OCR text:
```
%{ocr_text}
```
