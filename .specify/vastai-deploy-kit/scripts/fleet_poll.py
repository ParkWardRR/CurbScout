#!/usr/bin/env python3
"""
Fleet Status Poller — runs on your Mac, publishes to GCS.

Polls Vast.ai for live instance data, reads gallery_data.json for video counts,
and writes a combined fleet_status.json to GCS every 15 seconds.

Usage:
    python3 deploy/fleet_poll.py            # polls forever
    python3 deploy/fleet_poll.py --once     # single poll (for cron)

The dashboard (controller/index.html) reads fleet_status.json from GCS.
"""
import json, subprocess, sys, time, os
from datetime import datetime, timezone

GCS_BUCKET = "ph-test-2026"
GCS_STATUS_PATH = f"gs://{GCS_BUCKET}/fleet_status.json"
POLL_INTERVAL = 15  # seconds
VAST_CLI = os.path.expanduser("~/Library/Python/3.14/bin/vastai")

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")

def get_vast_instances():
    """Fetch instance list from Vast.ai API."""
    try:
        r = subprocess.run(
            [VAST_CLI, "show", "instances", "--raw"],
            capture_output=True, text=True, timeout=15
        )
        if r.returncode != 0:
            log(f"vastai error: {r.stderr[:200]}")
            return []
        return json.loads(r.stdout)
    except Exception as e:
        log(f"vastai exception: {e}")
        return []

def get_gallery_stats():
    """Read gallery_data.json from GCS and compute stats."""
    try:
        r = subprocess.run(
            ["gsutil", "cat", f"gs://{GCS_BUCKET}/gallery_data.json"],
            capture_output=True, text=True, timeout=10
        )
        if r.returncode != 0:
            return {"total_videos": 0, "by_host": {}, "by_workflow": {}}
        data = json.loads(r.stdout)
        outputs = data.get("outputs", {})
        from collections import Counter
        hosts = Counter(m.get("host", "unknown") for m in outputs.values())
        workflows = Counter(m.get("workflow", "unknown") for m in outputs.values())
        return {
            "total_videos": len(outputs),
            "by_host": dict(hosts),
            "by_workflow": dict(workflows),
        }
    except Exception as e:
        log(f"gallery read error: {e}")
        return {"total_videos": 0, "by_host": {}, "by_workflow": {}}

def get_gcs_video_counts():
    """Count MP4s per host directory in GCS outputs."""
    counts = {}
    try:
        r = subprocess.run(
            ["gsutil", "ls", f"gs://{GCS_BUCKET}/outputs/"],
            capture_output=True, text=True, timeout=10
        )
        dirs = [line.strip().rstrip("/").split("/")[-1]
                for line in r.stdout.strip().split("\n")
                if line.strip().endswith("/")]
        for d in dirs:
            r2 = subprocess.run(
                ["gsutil", "ls", f"gs://{GCS_BUCKET}/outputs/{d}/"],
                capture_output=True, text=True, timeout=10
            )
            mp4s = [l for l in r2.stdout.strip().split("\n") if l.endswith(".mp4")]
            counts[d] = len(mp4s)
    except Exception as e:
        log(f"GCS count error: {e}")
    return counts

def build_status():
    """Build combined fleet status JSON."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Get Vast.ai instances
    raw_instances = get_vast_instances()
    instances = []
    total_cost_hr = 0.0

    for inst in raw_instances:
        label = inst.get("label") or f"instance-{inst.get('id', '?')}"
        cost = inst.get("dph_total") or 0
        total_cost_hr += cost

        instances.append({
            "id": inst.get("id"),
            "label": label,
            "gpu_name": inst.get("gpu_name", "Unknown"),
            "gpu_util": inst.get("gpu_util") or 0,
            "cpu_util": inst.get("cpu_util") or 0,
            "ram_used_gb": round((inst.get("cpu_ram") or 0) / 1024, 1),
            "ram_total_gb": round((inst.get("cpu_ram") or 0) / 1024, 1),  # cpu_ram is in MB
            "disk_used_gb": round(inst.get("disk_usage") or 0, 1),
            "disk_total_gb": round(inst.get("disk_space") or 60, 1),
            "gpu_ram_total_mb": inst.get("gpu_ram") or 0,
            "num_gpus": inst.get("num_gpus") or 1,
            "cpu_name": inst.get("cpu_name") or "Unknown",
            "cpu_cores": inst.get("cpu_cores") or 0,
            "status": inst.get("actual_status") or "unknown",
            "cost_per_hr": round(cost, 4),
            "uptime_min": round((inst.get("duration") or 0) / 60000, 1),  # duration is in ms
            "ssh_host": inst.get("ssh_host") or "",
            "ssh_port": inst.get("ssh_port") or 0,
            "inet_down_mbps": round(inst.get("inet_down") or 0, 0),
            "inet_up_mbps": round(inst.get("inet_up") or 0, 0),
            "machine_id": inst.get("machine_id"),
            "geolocation": inst.get("geolocation") or "Unknown",
            "reliability": round(inst.get("reliability") or 0, 3),
            "docker_image": inst.get("image_uuid") or inst.get("image") or "",
        })

    # Get gallery stats
    gallery = get_gallery_stats()

    # Get GCS video counts
    gcs_counts = get_gcs_video_counts()

    # Merge GCS counts into gallery by_host
    for host, count in gcs_counts.items():
        if host not in gallery["by_host"]:
            gallery["by_host"][host] = 0
        gallery["by_host"][host] = max(gallery["by_host"].get(host, 0), count)

    # Build final status
    status = {
        "polled_at": now,
        "poll_source": "fleet_poll.py",
        "instances": sorted(instances, key=lambda x: x["label"]),
        "gallery": gallery,
        "gcs_video_counts": gcs_counts,
        "cost_summary": {
            "hourly_rate": round(total_cost_hr, 4),
            "active_count": len([i for i in instances if i["status"] == "running"]),
            "total_instances": len(instances),
        },
    }
    return status

def upload_status(status):
    """Upload fleet_status.json to GCS."""
    tmp = "/tmp/fleet_status.json"
    with open(tmp, "w") as f:
        json.dump(status, f, indent=2)

    r = subprocess.run(
        ["gsutil", "-h", "Content-Type:application/json",
         "-h", "Cache-Control:no-cache,max-age=0",
         "cp", tmp, GCS_STATUS_PATH],
        capture_output=True, text=True, timeout=10
    )
    if r.returncode != 0:
        log(f"Upload error: {r.stderr[:200]}")
        return False
    return True

def main():
    once = "--once" in sys.argv
    log(f"Fleet Poller started ({'once' if once else f'every {POLL_INTERVAL}s'})")

    while True:
        try:
            status = build_status()
            n = len(status["instances"])
            vids = status["gallery"]["total_videos"]
            cost = status["cost_summary"]["hourly_rate"]

            if upload_status(status):
                log(f"✅ {n} instances | {vids} videos | ${cost:.3f}/hr → GCS")
            else:
                log(f"⚠️  Upload failed, will retry")

        except Exception as e:
            log(f"❌ Error: {e}")

        if once:
            break
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
