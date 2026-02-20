# Match Meter Reading

You are extracting a utility meter reading from OCR text.
The meter may be an electricity, gas, or water meter.

## Context

The property has these meters:
%{meters_json}

Each meter entry: { id, label, identifier, meter_type, meter_group, unit, last_reading_kwh }

The `identifier` field is the physical serial number or label printed on the meter device. If the OCR text contains a serial number or device identifier, use it to match to the correct meter.

## Task

1. Find the numeric reading value in the OCR text
2. Match it to the most likely meter from the list
3. Use the last known readings as reference — the new reading should be
   >= the last reading (meters are cumulative, monotonically increasing)
4. For electricity meters: NT = low tariff (night), VT = high tariff (day) —
   if the OCR text or context suggests a tariff type, match accordingly
5. For gas meters: readings are in m³
6. For water meters: readings are in m³ or litres
7. A single image shows ONE meter reading. If the OCR contains
   multiple numbers, pick the one that looks like the main display reading

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
