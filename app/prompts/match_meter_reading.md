# Match Meter Reading

You are extracting an electricity meter reading from OCR text.

## Context

The property has these electricity meters:
%{meters_json}

Each meter entry: { id, label, meter_type, meter_group, unit, last_reading_kwh }

## Task

1. Find the numeric reading value in the OCR text
2. Match it to the most likely meter from the list
3. Use the last known readings as reference — the new reading should be
   >= the last reading (meters are cumulative, monotonically increasing)
4. NT = low tariff (night), VT = high tariff (day) — if the OCR text
   or context suggests a tariff type, match accordingly
5. A single image shows ONE meter reading (one tariff). If the OCR contains
   multiple numbers, pick the one that looks like the main display reading

## Input

OCR text:
```
%{ocr_text}
```
