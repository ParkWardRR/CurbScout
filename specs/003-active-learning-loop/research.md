# Research: Active Learning Loop

## Decisions

### 1. Triggering Mechanism
- **Decision**: Trigger the evaluation from a cron-scheduled endpoint on the GCP Hub (e.g., Cloud Scheduler calling `GET /api/jobs/evaluate-training`).
- **Rationale**: An event driver (like Firestore Triggers picking up every single correction) would be overkill and potentially race-condition heavy. A periodic eval check (daily/weekly) ensures batches are cleanly collected and the threshold `$AUTO_TRAIN_THRESHOLD` is evaluated precisely.
- **Alternatives considered**: Trigger on every correction write (too noisy); client-side trigger (relies on browser being open).

### 2. Lineage Tracking
- **Decision**: Introduce a `MODELS` collection in Firestore. When a dataset is compiled, all `sighting_id`s included are recorded as an array inside the Model document.
- **Rationale**: This gives deep auditability. If a model behaves erratically, data scientists can instantly locate exactly which user corrections poisoned it. 
- **Alternatives considered**: Log lineage to BigQuery (over-engineering), save to a text file in GCS (hard to query locally for dashboards).

### 3. State Management for Corrections
- **Decision**: Add a boolean `trained` flag to `SIGHTING`s that defaults to `false`. When included in a batch, toggle to `true`.
- **Rationale**: Prevents double-training on the same corrections across consecutive weeks, keeping epochs mathematically sane.

### 4. Deploy Hook / Webhook
- **Decision**: Use a dedicated `POST /api/webhooks/vast-export` endpoint authenticated via API Key.
- **Rationale**: Vast.ai ephemeral nodes need a secure way to notify the hub "I'm done, here's my GCS path". Once received, the Hub marks the model `status = 'deployed'`, triggering the M4's `sync_models.py` on its next tick to pull it down.
