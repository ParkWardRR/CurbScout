# Data Model: Active Learning Loop

**Feature**: `003-active-learning-loop`
**Date**: 2026-02-21

## Modifications to Datastore Schema

We are introducing the entity concepts of a **Machine Learning Model Version** and tracking the states of **Corrections** post-training to prevent duplication across datasets.

### `SIGHTING` (GCP Extension)

A single boolean flag controls inclusion logic.

- `trained: boolean` - (Default: `false`). Set to true natively on the document only *after* the GCP Hub explicitly sweeps it up to form a dataset payload.

### New Entity: `MODELS` (GCP Firestore)

Tracks the iterative genealogy of the training pipeline natively.

**Schema:**
```json
{
  "id": "model_uuid",
  "version": "yolov8n-finetune-v12",
  "status": "training", // 'training' | 'failed' | 'exported' | 'deployed'
  "job_id": "vast_ai_job_uuid",
  "accuracy_baseline": 0.88,
  "accuracy_new": 0.91,
  "gcs_uri": "gs://curbscout-models/v12/",
  "lineage_ids": ["sighting_uuid_1", "sighting_uuid_2", "..."], // Up to thousands
  "created_at": "ISO_8601",
  "deployed_at": "ISO_8601"
}
```

This model document operates functionally identically to the `Job` type but is the ultimate output artifact from any job typed as `'training'`.

### Data Lineage
By checking `lineage_ids`, the dashboard can immediately determine exactly which user corrections from what rides built `version-v12`. If `version-v12` hallucinates stop signs as cars, analysts can reverse proxy `lineage_ids` through the UI to identify flawed training corrections, revert them, flag them `trained: false`, and queue generation of `version-v13`.
