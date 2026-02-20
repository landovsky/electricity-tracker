# Classify Meter Image

You are analyzing OCR text extracted from a photo taken by a user who is
trying to record electricity meter readings at a family house.

## Task

Determine if this OCR text comes from a photo of an electricity meter display.

## Input

OCR text extracted from the image:
```
%{ocr_text}
```

## Rules

- Electricity meters typically show numeric readings (kWh), may have
  labels like "NT", "VT", tariff indicators, serial numbers
- Non-meter photos might show: walls, furniture, text documents,
  other appliances, blurry/dark images with little text
- If the OCR text is very short or empty, it's likely not a useful meter photo
