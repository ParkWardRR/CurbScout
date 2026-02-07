---
description: How to submit a batch of processing jobs to a Vast.ai GPU instance
---

# Submit Batch Workflow

## Architecture Overview

```
Local Mac (orchestrator)           Vast.ai GPU Instances
┌─────────────────┐               ┌─────────────────────┐
│ submit_*.py     │ ──SCP──►     │ /workspace/          │
│ workflow.json   │               │ ├── input/   (imgs)  │
│ inputs/         │ ──SCP──►     │ ├── output/  (outs)  │
│                 │               │ └── server  (:8188)  │
│ vast-sync-v4.sh │ ──SSH──►     │                     │
│ (runs locally!) │ polls output/ │                     │
│                 │ ──gsutil──►  │                     │
│ gallery_data.json◄────────────  └─────────────────────┘
└─────────────────┘                        │
        │                                  ▼
    GCS: gs://BUCKET/                GCS: outputs/<HOST>/
    ├── gallery_data.json
    └── outputs/
        ├── 4090-a/
        ├── 3090-e/
        └── 3090-f/
```

**CRITICAL**: The V4 sync script runs on YOUR MAC, not on the GPU instance.

## Steps

### 1. Upload Input Files to Instance

```bash
scp -o StrictHostKeyChecking=no -P <PORT> inputs/*.png root@<HOST>:/workspace/input/
gsutil -m cp inputs/*.png gs://BUCKET-inputs/batch1/
```

⚠️ **Filenames with parentheses or special chars will cause API 400 errors.** Rename first.

### 2. Create Submit Script

Save to `submit_<batch>.py`:

```python
#!/usr/bin/env python3
import json, urllib.request, time, os
from PIL import Image

WORKFLOW = json.load(open("/workspace/workflow.json"))

def get_orientation(image_filename):
    """Auto-detect orientation from input image. Runs ON GPU INSTANCE."""
    img_path = os.path.join("/workspace/input", image_filename)
    if os.path.islink(img_path):
        img_path = os.path.realpath(img_path)
    try:
        img = Image.open(img_path)
        w, h = img.size
        return (480, 832) if h > w else (832, 480)
    except:
        return 832, 480

def submit(job_id, seed, image, prompt):
    wf = json.loads(json.dumps(WORKFLOW))
    out_w, out_h = get_orientation(image)
    
    for nid, node in wf.items():
        ct = node.get("class_type", "")
        inp = node.get("inputs", {})
        if ct == "VHS_VideoCombine" and "filename_prefix" in inp:
            wf[nid]["inputs"]["filename_prefix"] = "output_" + job_id
        if ct == "KSampler":
            wf[nid]["inputs"]["seed"] = seed
            wf[nid]["inputs"]["steps"] = 4
        if "ImageToVideo" in ct:
            wf[nid]["inputs"]["height"] = out_h
            wf[nid]["inputs"]["width"] = out_w
            wf[nid]["inputs"]["length"] = 241
        if ct == "CLIPTextEncode" and "text" in inp and isinstance(inp["text"], str):
            wf[nid]["inputs"]["text"] = prompt
        if ct == "LoadImage" and "image" in inp:
            wf[nid]["inputs"]["image"] = image
    
    payload = json.dumps({"prompt": wf}).encode()
    req = urllib.request.Request("http://localhost:8188/prompt",
        data=payload, headers={"Content-Type": "application/json"})
    try:
        resp = json.loads(urllib.request.urlopen(req).read())
        orient = "portrait" if out_h > out_w else "landscape"
        print(f"  OK {job_id} ({out_w}x{out_h} {orient})")
    except Exception as e:
        print(f"  FAIL {job_id}: {e}")

jobs = [
    {"id": "job-001", "seed": 12345, "image": "input1.png",
     "prompt": "Your prompt here"},
]

for j in jobs:
    submit(j["id"], j["seed"], j["image"], j["prompt"])
    time.sleep(0.3)
```

### 3. Upload and Run Submit Script

```bash
scp -P <PORT> workflow.json submit_<batch>.py root@<HOST>:/workspace/
ssh -p <PORT> root@<HOST> 'cd /workspace && python3 submit_<batch>.py'
```

### 4. Start V4 Sync (from Mac)

```bash
nohup ./scripts/vast-sync-v4.sh <PORT> <SSH_HOST> BUCKET 30 <HOST_LABEL> > sync.log 2>&1 &
```

### 5. Monitor Progress

```bash
for spec in "ssh2.vast.ai:37012:4090-a" "ssh4.vast.ai:11406:3090-e"; do
  host=$(echo $spec | cut -d: -f1)
  port=$(echo $spec | cut -d: -f2)
  label=$(echo $spec | cut -d: -f3)
  timeout 10 ssh -o ConnectTimeout=3 -p $port root@$host \
    'gpu=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
     echo "'$label': GPU=$gpu"' 2>/dev/null
done
```

---

## Orientation Matching (CRITICAL)

**The #1 bug that wasted hours**: hardcoded landscape dimensions when inputs were portrait.

- **Portrait** (height > width) → `width=480, height=832`
- **Landscape** (width > height) → `width=832, height=480`
- **Square** → default to `width=832, height=480`

The `get_orientation()` function runs **ON THE GPU INSTANCE** — never check locally.

---

## File Deletion (Prevent Re-Sync Duplicates)

1. **Delete from instance local output FIRST**
2. **THEN delete from GCS**

```bash
ssh -p <PORT> root@<HOST> 'rm -f /workspace/output/<filename>.*'
gsutil rm gs://BUCKET/outputs/<HOST>/<filename>.*
```

---

## GCS Buckets

| Bucket | Purpose |
|--------|---------|
| `gs://BUCKET/outputs/<HOST>/` | Generated outputs (per-host dirs) |
| `gs://BUCKET/gallery_data.json` | Metadata with prompts, seeds, render times |
| `gs://BUCKET-inputs/` | Input images for jobs |

---

## Timing Reference

| GPU | Render Time (241 frames, 4 steps) | Cost/job |
|-----|-----------------------------------|----------|
| RTX 4090 | ~5-7 min | ~$0.04 |
| RTX 3090 | ~12-15 min | ~$0.04 |
