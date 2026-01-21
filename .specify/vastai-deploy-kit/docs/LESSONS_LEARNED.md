# Operational Knowledge — Lessons Learned

> Critical bugs, gotchas, and field-tested fixes from production Vast.ai deployments.

---

## 1. Duplicate Files in Output

**Root cause**: A legacy sync process running ON the GPU instance was continuously syncing to one path, while the V4 sync (from Mac) wrote to another path. Same files in both = duplicates.

**Fix**: Kill any rogue gsutil processes on the instance, only one sync path should ever be active.

**Prevention**: After provisioning, ALWAYS check for leftover sync processes:
```bash
ssh -p <PORT> root@<HOST> 'ps aux | grep gsutil | grep -v grep'
```

## 2. Wrong Output Orientation

**Root cause**: Submit scripts had hardcoded landscape dimensions. Portrait inputs (the majority) rendered as landscape, creating distorted output.

**Fix**: Added `get_orientation()` auto-detection that reads input images ON THE GPU INSTANCE:
```python
from PIL import Image

def get_orientation(image_filename):
    img_path = os.path.join("/workspace/input", image_filename)
    if os.path.islink(img_path):
        img_path = os.path.realpath(img_path)
    try:
        img = Image.open(img_path)
        w, h = img.size
        return (480, 832) if h > w else (832, 480)
    except:
        return 832, 480
```

**Prevention**: Never hardcode dimensions. Always use auto-detection.

## 3. Re-Sync After Deletion

**Root cause**: Deleting files from GCS but not from the instance's local output. The sync script re-uploads them on the next cycle.

**Fix**: Always delete from local output FIRST, then from GCS:
```bash
# 1. Delete local FIRST
ssh -p <PORT> root@<HOST> 'rm -f /workspace/output/<filename>.*'
# 2. THEN GCS
gsutil rm gs://BUCKET/outputs/<HOST>/<filename>.*
```

## 4. SSH Drops When Killing Processes

**Root cause**: Running `kill` or `pkill` on a server process via SSH can kill the SSH session itself.

**Fix**: Use a restart script via `nohup`:
```bash
scp -P <PORT> restart.sh root@<HOST>:/tmp/
ssh -p <PORT> root@<HOST> 'nohup bash /tmp/restart.sh > /dev/null 2>&1 & echo "PID: $!"'
```

## 5. Filenames with Special Characters

**Root cause**: Filenames with parentheses `()` or dashes `--` cause API 400 errors.

**Fix**: Rename files on the instance before submitting:
```bash
ssh -p <PORT> root@<HOST> 'mv "/workspace/input/file(1).png" "/workspace/input/file_1.png"'
```

## 6. 60GB Disk is NOT Enough

Models alone are ~35GB, plus download caches double during download. **Always provision ≥100GB.**

## 7. SSH Sluggish Under GPU Load

When the GPU is rendering at 100%, SSH to that instance can be extremely slow (30s+ response). Use short timeouts and small commands.

## 8. `imageio` Import Failures

**Root cause**: Python package `requirements.txt` installs can fail silently on flaky connections with SHA256 hash mismatches.

**Fix**: Explicit install with `--no-cache-dir` retry + verification:
```bash
pip install -q --no-cache-dir imageio imageio-ffmpeg
python3 -c "import imageio" || { echo "FATAL: imageio missing"; exit 1; }
```

## 9. opencv-python vs opencv-python-headless

**Root cause**: Docker images ship `opencv-python` which needs X11 libraries (`libxcb.so.1`), unavailable in containers.

**Fix**: Replace with headless version:
```bash
pip uninstall -y opencv-python 2>/dev/null || true
pip install opencv-python-headless
```

## 10. Instance Stuck in "loading"

Vast.ai instances frequently get stuck. Never wait more than 5 minutes.

| Duration | Action |
|----------|--------|
| < 3 min | Normal, wait |
| > 5 min | Junk — destroy immediately |

## 11. MJ CDN Images Can't Be Downloaded via curl

Some image CDN URLs require browser-like headers or don't work via `curl`/`wget`. Upload manually to your GCS input bucket first.

## 12. SSH Port Changes with New Instances

SSH port changes every time you create a new instance. Always check with `vastai show instances` before connecting.

## 13. gsutil Auth Differences

- **GPU instances**: Auth via service account key (`/root/.boto` or `GOOGLE_APPLICATION_CREDENTIALS`)
- **Local Mac**: Auth via `gcloud auth login`

## 14. Queue Shows 0 but GPU at 100%

API snapshot timing — the queue check happens between jobs. Check processing logs instead of trusting the queue API alone.

---

## Common Gotchas Summary

| # | Gotcha | Fix |
|---|--------|-----|
| 1 | Duplicate outputs | Kill rogue sync processes, only one sync path |
| 2 | Wrong orientation | Auto-detect with `get_orientation()` |
| 3 | Files re-appear after delete | Delete local FIRST, then GCS |
| 4 | SSH session killed | Use `nohup` wrapper for server restarts |
| 5 | Special char filenames | Rename before processing |
| 6 | Disk too small | Always ≥100GB |
| 7 | SSH slow under GPU load | Short timeouts, small commands |
| 8 | imageio missing | `pip install --no-cache-dir` + verify import |
| 9 | opencv X11 error | Use `opencv-python-headless` |
| 10 | Instance stuck loading | Destroy after 5 min |
| 11 | CDN images | Upload to GCS first |
| 12 | SSH port changed | Check `vastai show instances` |
| 13 | GCS auth mismatch | SA key on instances, gcloud on Mac |
| 14 | Queue API misleading | Check logs, not just queue endpoint |
