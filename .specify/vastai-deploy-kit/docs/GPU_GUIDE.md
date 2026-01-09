# GPU Configuration & Performance Guide

## GPU Comparison: RTX 4090 vs RTX 3090

### Identical Settings (both GPUs)

| Setting | Value | Notes |
|---------|-------|-------|
| Resolution | 832×480 | Native 480p |
| Output Length | 241 frames | ~10s at 24fps |
| Quantization | FP8 E4M3FN | Pre-quantized weights, fits 24GB |

### Performance Expectations

| Metric | RTX 4090 | RTX 3090 | Delta |
|--------|----------|----------|-------|
| **CUDA Compute** | 8.9 | 8.6 | 4090 newer arch |
| **VRAM** | 24GB GDDR6X | 24GB GDDR6X | Same |
| **Memory BW** | 1008 GB/s | 936 GB/s | 4090 ~8% faster |
| **FP16 TFLOPS** | 82.6 | 35.6 | 4090 ~2.3× faster |
| **Est. render time** | ~5–7 min | ~12–15 min | 3090 ~2× slower |
| **Cost/job** | ~$0.05 | ~$0.04 | 3090 cheaper per job |

### Key Takeaways

1. **Speed**: RTX 4090 is ~2× faster due to higher FP16 throughput. But cost per job is similar because 3090s rent for ~50% less.
2. **VRAM**: Both have 24GB, same models fit without changes.
3. **Strategy**: Use 4090 for iteration/testing (faster turnaround), 3090 fleet for bulk parallel renders (better $/job for large batches).

## A100 80GB Notes

| Setting | 3090 (24GB) | A100 (80GB) |
|---------|-------------|-------------|
| Resolution | 480×832 | **720×1280** |
| Frames | 241 | **301** (25% more) |
| Steps | 4 | **6** (50% more quality) |
| Cost | $0.11–0.18/hr | $0.78/hr |

### A100 Disk Requirements
Minimum **100GB disk**. A 50GB instance WILL run out of space.

| Component | Size |
|-----------|------|
| Large model (checkpoint) | ~23 GB |
| Text encoder | ~6.3 GB |
| CLIP Vision | ~1.2 GB |
| VAE | ~243 MB |
| **Total models** | **~31 GB** |
| Input images + outputs | ~2 GB |
| Processing pipeline + deps | ~5 GB |
| **Total minimum** | **~38 GB + headroom** |

## Host Label Convention

| Pattern | Meaning |
|---------|---------|
| `4090-a` | First RTX 4090 instance |
| `3090-b` | Second overall, RTX 3090 |
| `run3-a` | Deployment run 3, host A |
| `a100-x` | A100 instance |

Labels are embedded in `gallery_data.json` and used in GCS output paths.

## Provisioning Workflow

```bash
# 1. Launch via CLI or launch script
vastai create instance <OFFER_ID> --image pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime --disk 100

# 2. Wait for boot, then SSH in
ssh -o StrictHostKeyChecking=no -p <PORT> root@<HOST> 'echo OK && nvidia-smi'

# 3. Upload workflow + input files
scp -P <PORT> workflow.json submit.py root@<HOST>:/workspace/
scp -P <PORT> inputs/*.jpg root@<HOST>:/workspace/input/

# 4. Start sync with unique host label
nohup scripts/vast-sync-v4.sh <PORT> <HOST> BUCKET 30 <LABEL> > sync.log 2>&1 &

# 5. Submit jobs
ssh -p <PORT> root@<HOST> 'cd /workspace && python3 submit.py'
```

### Kill Junk Instances

```bash
# Via Go CLI
go run cmd/vastctl/main.go list
go run cmd/vastctl/main.go destroy <ID>

# Via API
curl -X DELETE -H "Authorization: Bearer $(cat ~/.config/promptharbor/vast_api_key)" \
  "https://console.vast.ai/api/v0/instances/<ID>/"
```
