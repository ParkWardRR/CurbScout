# Data Model: Curb Intelligence

**Feature**: `002-curb-intelligence`
**Date**: 2026-02-21

## Modifications to SQLite & Firestore Schemas

We can reuse the `SIGHTING` schema by altering its semantic payload, or introduce a new `INTELLIGENCE_EVENT` variant to keep Vehicles separated from Signs and Hazards. Given the instruction to reuse architecture, we will extend the `SIGHTING` logic to handle arbitrary classes via `attrs_json`.

### `DETECTION` (SQLite Extension)

- The target classes expanded from `car, truck, bus, motorcycle` to include: `parking_sign`, `storefront_awning`, `pothole`, `bike_lane_obstruction`, `construction_cone`.

### `SIGHTING` (SQLite & Firestore Extension)

If a detection is mapped to `parking_sign`, the Sighting transforms accordingly:
- `predicted_make` becomes the class (e.g. `parking_sign`).
- `predicted_model` becomes the OCR raw string.
- `attrs_json` contains the parsed location rules map:
  ```json
  {
      "rules": {
          "type": "paid_parking",
          "duration_hours": 2,
          "start_time": "08:00",
          "end_time": "18:00",
          "exceptions": ["sunday", "holidays"]
      }
  }
  ```

If a detection represents a hazard:
- `predicted_make` = `hazard`
- `predicted_model` = `pothole` | `bike_lane_obstruction`
- `sanity_warning` flags automatically if `bike_lane_obstruction` confidence > 90%.

### Dashboard Visualization
When the GCP Hub queries `sightings` for Mapbox:
- Vehicle symbols use blue pins.
- Hazard symbols use red hazard warning pins.
- Parking Signs use green/gray parking icons.

This ensures zero necessary changes to the upstream database architectures (SQLite schemas/Firestore schemas) beyond storing different string schemas inside the flexible JSON dictionaries already deployed locally.
