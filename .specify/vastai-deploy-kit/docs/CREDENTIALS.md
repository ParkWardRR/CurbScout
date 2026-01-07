# API Keys & Credentials Reference

## Secret Manager (Google Cloud)

All secrets live in **Google Cloud Secret Manager** under your GCP project.

| Secret Name | Description | Used By |
|-------------|-------------|---------|
| `vast-api-key` | Vast.ai API key for instance management + auto-kill | `bootstrap_autonomous.sh`, `instant_gcs_sync.sh` |
| `huggingface-token` | HuggingFace token for gated model downloads | `bootstrap_autonomous.sh` |
| `civitai-api-key` | CivitAI API key (optional, for future integrations) | — |

## Accessing Secrets

### From GPU Instances (via gcloud + SA)
```bash
# The bootstrap script auto-fetches via fetch_secret():
gcloud secrets versions access latest \
  --secret="vast-api-key" \
  --project="YOUR_PROJECT"
```

### From Local Machine
```bash
# Stored locally at ~/.config/promptharbor/ (chmod 600)
cat ~/.config/promptharbor/vast_api_key
cat ~/.config/promptharbor/huggingface_token
cat ~/.config/promptharbor/civitai_api_key
```

### From Go SDK
```go
// Uses config.Load() which checks: env var → config file → key file
cfg, _ := config.Load("config.yaml")
apiKey := cfg.VastAI.APIKey // resolved automatically
```

## Service Accounts

| Account | Role | Access |
|---------|------|--------|
| `ph-vast-uploader@PROJECT.iam.gserviceaccount.com` | `storage.objectCreator` | Write to `gs://BUCKET` |
| Same SA | `secretmanager.secretAccessor` | Read `vast-api-key` secret |

## Adding a New Secret
```bash
echo -n "YOUR_SECRET_VALUE" | \
  gcloud secrets create <secret-name> \
    --project=YOUR_PROJECT \
    --data-file=- \
    --replication-policy=automatic

# Also store locally:
echo -n "YOUR_SECRET_VALUE" > ~/.config/promptharbor/<secret_name>
chmod 600 ~/.config/promptharbor/<secret_name>
```

## Rotating a Secret
```bash
echo -n "NEW_VALUE" | \
  gcloud secrets versions add <secret-name> \
    --project=YOUR_PROJECT \
    --data-file=-

# Update local copy:
echo -n "NEW_VALUE" > ~/.config/promptharbor/<secret_name>
```

## Security Rules
1. **NEVER** hardcode secrets in scripts or committed files
2. **NEVER** pass secrets as CLI arguments (visible in `ps`)
3. **NEVER** log secret values — log "present (redacted)" only
4. **ALWAYS** use `fetch_secret()` in bootstrap scripts
5. **ALWAYS** use Secret Manager or `~/.config/promptharbor/` locally
6. GCS SA key file should be migrated from public GCS to Secret Manager
