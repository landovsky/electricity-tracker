# Classify Meter Image

You are analyzing OCR text extracted from a photo taken by a user who is
trying to record utility meter readings at a family house.

## Task

Determine if this OCR text comes from a photo of a utility meter display
(electricity, gas, or water).

## Input

OCR text extracted from the image:
```
%{ocr_text}
```

## Rules

- Electricity meters typically show numeric readings (kWh), may have
  labels like "NT", "VT", tariff indicators, serial numbers
- Gas meters show readings in m³, may mention gas distributors, kPa, m³/h
- Water meters show readings in m³ or litres
- Non-meter photos might show: walls, furniture, text documents,
  other appliances, blurry/dark images with little text
- If the OCR text is very short or empty, it's likely not a useful meter photo
