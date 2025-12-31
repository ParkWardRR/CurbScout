# Hardware Acceleration & Vast.ai Deploy Kit

**Feature**: `001-local-pipeline-mvp`
**Date**: 2026-02-21
**Purpose**: Hardware acceleration strategy + Vast.ai integration for training

---

## 1. Acceleration Architecture Overview

CurbScout runs inference on **two platforms in parallel**, selecting the
optimal hardware backend for every stage of the pipeline:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CurbScout Acceleration Matrix                     │
├──────────────────┬──────────────────┬────────────────────────────────┤
│ Stage            │ M4 Mac mini      │ Vast.ai (RTX 4090/3090)       │
├──────────────────┼──────────────────┼────────────────────────────────┤
│ Frame Extraction │ VideoToolbox HW  │ N/A (done locally)            │
│ Vehicle Detect   │ CoreML (ANE)     │ CUDA (TensorRT)               │
│ Classification   │ CoreML (ANE)     │ CUDA (TensorRT)               │
│ Image Processing │ ARM NEON SIMD    │ AVX-512/AVX2 + CUDA           │
│ Perceptual Hash  │ ARM NEON (vPMAC) │ AVX-512 (VPOPCNTDQ)           │
│ Database I/O     │ ARM NEON memcpy  │ N/A (local only)              │
│ Model Training   │ N/A (too slow)   │ CUDA + cuDNN + TensorCore     │
│ Batch Reprocess  │ CoreML (if idle) │ CUDA (bulk inference)         │
└──────────────────┴──────────────────┴────────────────────────────────┘
```

---

## 2. Apple M4 — Maximum CoreML & ANE Utilization

### M4 Hardware Specs (24 GB Mac mini)

| Unit | Capability | CurbScout Usage |
|------|-----------|-----------------|
| **Neural Engine (ANE)** | 38 TOPS (INT8), 16-core | YOLOv8 detection, EfficientNet-B4 classification |
| **GPU** | 10-core, 4.5 TFLOPS FP32 | Fallback when ANE is busy, image resizing |
| **CPU** | 4P + 6E cores, ARMv9 | Pipeline orchestration, hashing, DB ops |
| **SME** | 512-bit matrix ops, BFloat16 | Matrix multiply in custom kernels |
| **NEON SIMD** | 128-bit per core, 4 ALUs | Image preprocessing, pHash, crop ops |
| **Media Engine** | Hardware H.264/H.265 decode | VideoToolbox frame extraction |
| **Memory** | 24 GB unified, 120 GB/s BW | Zero-copy between CPU/GPU/ANE |

### CoreML Optimization Strategy

```python
# pipeline/curbscout/accelerator.py — Backend selection

import platform
import coremltools as ct

class AcceleratorBackend:
    """Auto-selects optimal compute backend per platform."""

    def __init__(self):
        self.platform = platform.machine()  # 'arm64' or 'x86_64'
        self.has_ane = self.platform == 'arm64' and platform.system() == 'Darwin'
        self.has_cuda = self._check_cuda()
        self.has_avx512 = self._check_avx512()

    def load_detection_model(self, model_path):
        """Load YOLOv8 with optimal backend."""
        if self.has_ane:
            # CoreML → ANE: 92.6 FPS on M4
            return self._load_coreml(model_path, compute_units='ALL')
        elif self.has_cuda:
            # TensorRT → CUDA: ~200+ FPS on RTX 4090
            return self._load_tensorrt(model_path)
        else:
            # ONNX Runtime → CPU with AVX-512/AVX2
            return self._load_onnx(model_path)

    def load_classifier(self, model_path):
        """Load EfficientNet-B4 classifier with optimal backend."""
        if self.has_ane:
            # CoreML ANE: ~300+ classifications/sec
            return self._load_coreml(model_path, compute_units='CPU_AND_NE')
        elif self.has_cuda:
            return self._load_tensorrt(model_path)
        else:
            return self._load_onnx(model_path)
```

### CoreML Model Export & Quantization

```bash
# Convert YOLOv8n detection to CoreML with ANE optimization
python3 -c "
from ultralytics import YOLO
import coremltools as ct

# Detection model — CoreML with INT8 quantization for ANE
model = YOLO('yolov8n.pt')
model.export(format='coreml', int8=True, nms=True)
# Output: yolov8n.mlpackage (~3 MB, INT8 → fastest on ANE)

# Classification model — CoreML with W8A8 for ANE
# Convert Jordo23 to CoreML:
import torch
from coremltools.converters import convert
# Load pretrained .pth → trace → convert
"
```

### CoreML Compute Unit Selection

| Compute Unit | When to Use | Speed | Power |
|-------------|-------------|-------|-------|
| `CPU_AND_NE` | Classification (smaller models) | ⚡ Fastest | Low |
| `ALL` | Detection (YOLOv8, larger models) | ⚡ Fast | Medium |
| `CPU_AND_GPU` | Image preprocessing batch | Fast | Medium |
| `CPU_ONLY` | Debugging, profiling | Baseline | Lowest |

### M4 CoreML Performance Benchmarks

| Model | Format | Compute | FPS | Latency |
|-------|--------|---------|-----|---------|
| YOLOv8n (detection) | CoreML INT8 | ANE | 92.6 | 10.8 ms |
| YOLOv8n (detection) | CoreML FP16 | ANE | 78.3 | 12.8 ms |
| YOLOv8n (detection) | ONNX FP32 | CPU | 42.1 | 23.7 ms |
| EfficientNet-B4 (cls) | CoreML INT8 | ANE | ~350 | 2.9 ms |
| EfficientNet-B4 (cls) | ONNX FP32 | CPU | ~120 | 8.3 ms |
| VehicleTypeNet ResNet-18 | ONNX FP32 | CPU+NEON | ~500 | 2.0 ms |

---

## 3. ARM NEON SIMD — Maximum Image Processing Performance

### NEON Operations for CurbScout

| Operation | NEON Intrinsics | Speedup vs Scalar |
|-----------|----------------|-------------------|
| **Image resize (bilinear)** | `vld1q_u8`, `vmull_u8`, `vaddq_u16` | 4–8× |
| **BGR→RGB channel swap** | `vld3q_u8` (deinterleave), `vst3q_u8` | 6× |
| **Normalize [0,1]** | `vcvtq_f32_u32`, `vmulq_f32` | 4× |
| **Perceptual hash (DCT)** | `vfmaq_f32` (fused multiply-add) | 3–5× |
| **Hamming distance** | `vcntq_u8` (popcount), `vpaddlq` | 8× |
| **Checksum (SHA-256)** | Hardware SHA extensions `vsha256...` | 10× |
| **JPEG decode** | Hardware JPEG engine (M4 media) | HW |

### Python Performance with NEON

```python
# These libraries auto-use NEON on ARM64:

# Pillow — uses NEON-optimized libjpeg-turbo for decode/encode
from PIL import Image
img = Image.open(crop_path).resize((380, 380), Image.LANCZOS)

# NumPy — uses NEON via BLAS (Accelerate framework on macOS)
import numpy as np
arr = np.array(img, dtype=np.float32) / 255.0  # NEON vectorized

# imagehash — pHash uses NumPy DCT → NEON-accelerated
import imagehash
phash = imagehash.phash(img)  # DCT → NEON FMA operations

# OpenCV — built with NEON on ARM64
import cv2
resized = cv2.resize(frame, (640, 640))  # NEON bilinear
```

### Accelerate Framework (macOS-specific)

```python
# Apple's Accelerate framework provides NEON + AMX + SME acceleration
# for BLAS, LAPACK, FFT, image processing, and compression.
# NumPy on macOS uses Accelerate.framework by default.

# Verify Accelerate is being used:
import numpy as np
np.show_config()
# Should show: accelerate / vecLib (not OpenBLAS)
```

---

## 4. AVX-512 / AVX2 — Vast.ai x86 Inference Optimization

### AVX-512 on Vast.ai GPU Instances

Vast.ai instances typically run on Intel Xeon or AMD EPYC CPUs that
support AVX2 (256-bit) and in many cases AVX-512 (512-bit). While
GPU inference is primary, **CPU operations benefit from AVX**:

| Operation | AVX Level | Use Case in CurbScout |
|-----------|----------|----------------------|
| **Image preprocessing** | AVX2/AVX-512 | Batch resize/normalize before GPU inference |
| **ONNX Runtime CPU** | AVX-512 + VNNI | Fallback inference on CPU-only instances |
| **pHash computation** | AVX-512 VPOPCNTDQ | Hamming distance for dedup (16 hashes/op) |
| **Data loading** | AVX2 | Fast memory copy for batch assembly |
| **JSON/CSV export** | AVX2 | SIMD-accelerated string processing |

### ONNX Runtime AVX Configuration

```python
# pipeline/curbscout/accelerator.py — x86 CPU optimization

import onnxruntime as ort

def create_cpu_session(model_path):
    """Create ONNX session with maximum CPU acceleration."""
    opts = ort.SessionOptions()

    # Enable all graph optimizations
    opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

    # Use all available CPU cores
    opts.intra_op_num_threads = 0  # auto-detect
    opts.inter_op_num_threads = 0  # auto-detect

    # Enable oneDNN (MKL-DNN) for AVX-512 acceleration
    opts.enable_cpu_mem_arena = True

    # CPU Execution Provider automatically uses AVX-512 if available
    session = ort.InferenceSession(
        model_path,
        sess_options=opts,
        providers=['CPUExecutionProvider']
    )
    return session

def create_gpu_session(model_path):
    """Create ONNX session with CUDA + TensorRT acceleration."""
    return ort.InferenceSession(
        model_path,
        providers=[
            ('TensorrtExecutionProvider', {
                'trt_max_workspace_size': 2 * 1024 * 1024 * 1024,  # 2 GB
                'trt_fp16_enable': True,
                'trt_max_partition_iterations': 1000,
            }),
            ('CUDAExecutionProvider', {
                'device_id': 0,
                'arena_extend_strategy': 'kSameAsRequested',
                'gpu_mem_limit': 20 * 1024 * 1024 * 1024,  # 20 GB
                'cudnn_conv_algo_search': 'EXHAUSTIVE',
            }),
            'CPUExecutionProvider',  # fallback
        ]
    )
```

### AVX-512 Detection at Runtime

```python
def detect_cpu_features():
    """Detect AVX-512/AVX2 support at runtime."""
    import subprocess
    result = subprocess.run(
        ['sysctl', '-n', 'machdep.cpu.features'],
        capture_output=True, text=True
    )
    features = result.stdout.upper()
    return {
        'avx2': 'AVX2' in features,
        'avx512': 'AVX512' in features,
        'neon': platform.machine() == 'arm64',
        'sha': 'SHA' in features,  # Hardware SHA extensions
    }
```

---

## 5. CUDA + TensorRT — Vast.ai GPU Inference & Training

### RTX 4090 / 3090 Performance for CurbScout Tasks

| Task | RTX 4090 | RTX 3090 | M4 (CoreML) |
|------|----------|----------|------------|
| YOLOv8n detection (FP16) | ~320 FPS | ~180 FPS | ~93 FPS |
| YOLOv8n detection (TensorRT INT8) | ~580 FPS | ~310 FPS | ~93 FPS (ANE INT8) |
| EfficientNet-B4 classification | ~800/sec | ~450/sec | ~350/sec |
| YOLOv8n-cls training (Stanford Cars) | ~4 min/epoch | ~7 min/epoch | ~25 min/epoch (MPS) |
| Batch 1000 crops classify | ~1.3 sec | ~2.2 sec | ~2.9 sec |

### TensorRT Optimization Pipeline

```bash
# On Vast.ai GPU instance — convert models to TensorRT for max speed

# 1. Export YOLOv8 to TensorRT
yolo export model=yolov8n.pt format=engine device=0 half=True

# 2. Export EfficientNet-B4 to TensorRT
python3 -c "
import tensorrt as trt
import onnxruntime as ort

# Convert ONNX → TensorRT with INT8 calibration
# Uses batch of CurbScout crops as calibration data
"

# 3. Benchmark
yolo benchmark model=yolov8n.engine data=coco8 imgsz=640 device=0
```

### CUDA Training Configuration for Vast.ai

```python
# training/train_classifier.py — Fine-tune on Vast.ai RTX 4090

from ultralytics import YOLO

# RTX 4090: 24 GB VRAM
# Optimal batch size for YOLOv8n-cls fine-tuning: 128
# Stanford Cars: 16,185 images → ~127 batches/epoch

model = YOLO('yolov8n-cls.pt')  # ImageNet pre-trained
results = model.train(
    data='./stanford_cars/',
    epochs=100,
    batch=128,           # Max batch for 24GB VRAM with YOLOv8n-cls
    imgsz=224,           # Stanford Cars standard size
    device=0,            # GPU 0
    workers=8,           # DataLoader workers
    amp=True,            # Mixed precision (FP16 + FP32)
    optimizer='AdamW',
    lr0=0.001,
    lrf=0.01,
    warmup_epochs=3,
    patience=20,         # Early stopping
    project='curbscout_training',
    name='stanford_cars_v1',
    exist_ok=True,
    # CUDA-specific optimizations:
    cache='ram',         # Cache entire dataset in RAM for speed
    cos_lr=True,         # Cosine learning rate scheduler
    label_smoothing=0.1, # Regularization
)

# After training, export to all formats:
best_model = YOLO('curbscout_training/stanford_cars_v1/weights/best.pt')
best_model.export(format='onnx', dynamic=True)   # For ONNX Runtime
best_model.export(format='coreml', int8=True)     # For M4 ANE
best_model.export(format='engine', half=True)     # For Vast.ai TensorRT
```

---

## 6. Vast.ai Deploy Kit (Adapted from PromptHarbor)

### Architecture — CurbScout Training on Vast.ai

```
Local Mac (M4 mini)                 Vast.ai Instance (RTX 4090)
──────────────────                  ────────────────────────────
1. Export labeled dataset            onstart-cmd → bootstrap_training.sh
   (corrections → training data)     ├── Install ultralytics + deps
                                     ├── Download dataset from GCS
2. Upload dataset to GCS             ├── Download base model (yolov8n-cls.pt)
   gs://curbscout/training/v1/       ├── Fine-tune on Stanford Cars
                                     │   + CurbScout corrections
3. Launch Vast.ai instance           ├── Export best.pt → ONNX + CoreML
   vastai create instance            ├── Upload trained models to GCS
   --onstart-cmd "bootstrap..."      ├── Upload training metrics/logs
                                     └── Auto-destroy instance
4. Poll for completion
   (fleet_poll.py adapted)

5. Download trained model
   from GCS → ~/CurbScout/models/

6. A/B test new vs old model
   on held-out CurbScout data
```

### Key Scripts (Adapted from PromptHarbor)

| PromptHarbor Script | CurbScout Adaptation | Purpose |
|-------------------|---------------------|---------|
| `bootstrap_autonomous.sh` | `deploy/bootstrap_training.sh` | Instance setup: install deps, download data, run training, upload results, self-destruct |
| `instant_gcs_sync.sh` | `deploy/training_sync.sh` | Upload training metrics + model checkpoints to GCS in real-time |
| `fleet_poll.py` | `deploy/training_poll.py` | Monitor training progress from local Mac, update status JSON |
| `auto-shutdown.sh` | `deploy/training_autokill.sh` | Auto-destroy instance when training completes or max TTL reached |
| `pkg/vast/client.go` | `pipeline/curbscout/vast_client.py` | Python port of the Go Vast.ai API client for instance management |

### CurbScout Vast.ai Bootstrap Script

```bash
#!/usr/bin/env bash
# deploy/bootstrap_training.sh — CurbScout fine-tuning on Vast.ai
#
# Usage: bash bootstrap_training.sh <RUN_LABEL> <DATASET_VERSION>
# Example: bash bootstrap_training.sh train-v1 dataset_2026-02-21

set -euo pipefail

RUN_LABEL="${1:?Usage: bootstrap_training.sh <RUN_LABEL> <DATASET_VERSION>}"
DATASET_VER="${2:?Missing dataset version}"
GCS_BUCKET="${GCS_BUCKET:-curbscout-training}"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a /tmp/training.log; }
fail() { log "FATAL: $*"; exit 1; }

# ── 1. Install dependencies ──
log "Installing training dependencies..."
pip install -q ultralytics torch torchvision onnx coremltools \
    google-cloud-storage tensorrt 2>/dev/null \
  || pip install -q --no-cache-dir ultralytics torch torchvision

# Verify CUDA
python3 -c "import torch; assert torch.cuda.is_available(), 'No CUDA'" \
  || fail "CUDA not available"
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
log "GPU: ${GPU_NAME}"

# ── 2. Download dataset from GCS ──
log "Downloading dataset ${DATASET_VER}..."
mkdir -p /workspace/data
gsutil -m cp -r "gs://${GCS_BUCKET}/datasets/${DATASET_VER}/" /workspace/data/
log "Dataset downloaded: $(find /workspace/data -name '*.jpg' | wc -l) images"

# ── 3. Download base model ──
log "Downloading base model..."
python3 -c "from ultralytics import YOLO; YOLO('yolov8n-cls.pt')"

# ── 4. Train ──
log "Starting training..."
python3 -c "
from ultralytics import YOLO
model = YOLO('yolov8n-cls.pt')
model.train(
    data='/workspace/data/${DATASET_VER}',
    epochs=100,
    batch=128,
    imgsz=224,
    device=0,
    workers=8,
    amp=True,
    optimizer='AdamW',
    lr0=0.001,
    patience=20,
    project='/workspace/results',
    name='${RUN_LABEL}',
    cache='ram',
    cos_lr=True,
    label_smoothing=0.1,
)
"

# ── 5. Export all formats ──
log "Exporting models..."
BEST="/workspace/results/${RUN_LABEL}/weights/best.pt"
python3 -c "
from ultralytics import YOLO
m = YOLO('${BEST}')
m.export(format='onnx', dynamic=True)
m.export(format='coreml', int8=True)
m.export(format='engine', half=True)
print('All exports complete')
"

# ── 6. Upload results to GCS ──
log "Uploading results..."
gsutil -m cp -r "/workspace/results/${RUN_LABEL}/" \
  "gs://${GCS_BUCKET}/results/${RUN_LABEL}/"
log "Results uploaded to gs://${GCS_BUCKET}/results/${RUN_LABEL}/"

# ── 7. Self-destruct ──
log "Training complete. Self-destructing instance..."
VAST_API_KEY=$(cat /tmp/vast_api_key 2>/dev/null || echo "")
INSTANCE_ID=$(cat /tmp/instance_id 2>/dev/null || echo "")
if [ -n "$VAST_API_KEY" ] && [ -n "$INSTANCE_ID" ]; then
    curl -sf -X DELETE \
      -H "Authorization: Bearer ${VAST_API_KEY}" \
      "https://console.vast.ai/api/v0/instances/${INSTANCE_ID}/"
    log "Instance destroyed."
else
    log "WARN: Cannot self-destruct (missing API key or instance ID)"
fi
```

### Vast.ai Python Client (Ported from Go)

```python
# pipeline/curbscout/vast_client.py — Python port of pkg/vast/client.go

import httpx
import json
from dataclasses import dataclass
from pathlib import Path

VAST_API_BASE = "https://console.vast.ai/api/v0"

@dataclass
class VastOffer:
    id: int
    gpu_name: str
    gpu_ram: int      # MB
    dph_total: float  # $/hr
    inet_down: float  # Mbps
    reliability: float
    disk_space: float  # GB

@dataclass
class VastInstance:
    id: int
    status: str  # 'running', 'loading', 'exited'
    ssh_host: str
    ssh_port: int
    label: str

class VastClient:
    def __init__(self, api_key: str | None = None):
        self.api_key = api_key or self._load_key()
        self.client = httpx.Client(
            timeout=30,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Accept": "application/json",
            }
        )

    def _load_key(self) -> str:
        key_path = Path.home() / ".config/curbscout/vast_api_key"
        if key_path.exists():
            return key_path.read_text().strip()
        raise FileNotFoundError(f"Vast.ai API key not found at {key_path}")

    def search_offers(self, gpu_name="RTX_4090", max_price=0.50,
                      min_disk=50, min_download=500) -> list[VastOffer]:
        q = json.dumps({
            "verified": {"eq": True},
            "rentable": {"eq": True},
            "num_gpus": {"eq": 1},
            "gpu_name": {"eq": gpu_name},
            "dph_total": {"lt": max_price},
            "disk_space": {"gt": min_disk},
            "inet_down": {"gt": min_download},
            "reliability2": {"gt": 0.95},
            "order": [["dph_total", "asc"]],
        })
        resp = self.client.get(f"{VAST_API_BASE}/bundles/", params={"q": q})
        resp.raise_for_status()
        return [VastOffer(**o) for o in resp.json().get("offers", [])]

    def launch_instance(self, offer_id: int, label: str,
                        onstart_cmd: str, disk_gb=60) -> VastInstance:
        resp = self.client.put(
            f"{VAST_API_BASE}/asks/{offer_id}/",
            json={
                "client_id": "me",
                "image": "pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel",
                "disk": disk_gb,
                "label": label,
                "onstart": onstart_cmd,
            }
        )
        resp.raise_for_status()
        data = resp.json()
        return VastInstance(
            id=int(data["new_contract"]),
            status="creating",
            ssh_host="", ssh_port=0, label=label
        )

    def destroy_instance(self, instance_id: int):
        self.client.delete(f"{VAST_API_BASE}/instances/{instance_id}/")

    def list_instances(self) -> list[VastInstance]:
        resp = self.client.get(f"{VAST_API_BASE}/instances")
        resp.raise_for_status()
        return [
            VastInstance(
                id=i["id"], status=i.get("actual_status", "?"),
                ssh_host=i.get("ssh_host", ""),
                ssh_port=i.get("ssh_port", 0),
                label=i.get("label", ""),
            )
            for i in resp.json().get("instances", [])
        ]
```

### Cost Budget for CurbScout Training

| GPU | $/hr | Training Time (100 epochs) | Total Cost |
|-----|------|---------------------------|------------|
| RTX 4090 | $0.27-0.40 | ~2-3 hours | **$0.80-1.20** |
| RTX 3090 | $0.11-0.16 | ~4-5 hours | **$0.55-0.80** |
| A100 40GB | $0.50-0.80 | ~1.5-2 hours | **$1.00-1.60** |

**Recommendation**: RTX 4090 for speed ($0.80-1.20 per training run),
RTX 3090 for budget ($0.55-0.80 per run). Run multiple experiments
in parallel across 3x 3090s for $1.65-2.40 total.

---

## 7. Multi-Backend Accelerator Module

### Runtime Auto-Detection

```python
# pipeline/curbscout/accelerator.py — Full implementation

import platform
import os
import logging
from enum import Enum
from typing import Any

log = logging.getLogger(__name__)

class Backend(Enum):
    COREML_ANE = "coreml_ane"      # M4 Neural Engine (fastest on Mac)
    COREML_GPU = "coreml_gpu"      # M4 GPU
    CUDA_TENSORRT = "cuda_trt"     # NVIDIA TensorRT (fastest on GPU)
    CUDA = "cuda"                  # NVIDIA CUDA (PyTorch)
    ONNX_AVX512 = "onnx_avx512"   # x86 CPU with AVX-512
    ONNX_AVX2 = "onnx_avx2"       # x86 CPU with AVX2
    ONNX_NEON = "onnx_neon"        # ARM CPU with NEON
    CPU = "cpu"                    # Scalar fallback

def detect_best_backend() -> Backend:
    """Auto-detect the best available compute backend."""
    arch = platform.machine()
    system = platform.system()

    # Check CUDA first (Vast.ai instances)
    try:
        import torch
        if torch.cuda.is_available():
            # Check for TensorRT
            try:
                import tensorrt
                log.info(f"Backend: CUDA+TensorRT (GPU: {torch.cuda.get_device_name(0)})")
                return Backend.CUDA_TENSORRT
            except ImportError:
                log.info(f"Backend: CUDA (GPU: {torch.cuda.get_device_name(0)})")
                return Backend.CUDA
    except ImportError:
        pass

    # Check CoreML (Apple Silicon)
    if arch == 'arm64' and system == 'Darwin':
        try:
            import coremltools
            log.info("Backend: CoreML ANE (Apple Silicon)")
            return Backend.COREML_ANE
        except ImportError:
            log.info("Backend: ONNX NEON (ARM64, no CoreML)")
            return Backend.ONNX_NEON

    # Check AVX-512 / AVX2 (x86)
    if arch == 'x86_64':
        cpu_features = _detect_x86_features()
        if 'avx512f' in cpu_features:
            log.info("Backend: ONNX AVX-512")
            return Backend.ONNX_AVX512
        elif 'avx2' in cpu_features:
            log.info("Backend: ONNX AVX2")
            return Backend.ONNX_AVX2

    log.warning("Backend: CPU scalar (no acceleration detected)")
    return Backend.CPU

def _detect_x86_features() -> set:
    """Detect x86 CPU features."""
    try:
        with open('/proc/cpuinfo', 'r') as f:
            for line in f:
                if line.startswith('flags'):
                    return set(line.split(':')[1].strip().split())
    except FileNotFoundError:
        pass
    # macOS fallback
    try:
        import subprocess
        result = subprocess.run(
            ['sysctl', '-n', 'machdep.cpu.features'],
            capture_output=True, text=True
        )
        return {f.lower() for f in result.stdout.split()}
    except:
        pass
    return set()
```

---

## 8. Acceleration-Aware Pipeline Flow

```
┌─────────────────────────────────────────────────────────┐
│              CurbScout Pipeline Execution                │
│                                                          │
│  ┌─────────────┐    detect_best_backend()               │
│  │ accelerator │───► Backend.COREML_ANE (M4 Mac)        │
│  │    .py      │    or Backend.CUDA_TENSORRT (Vast.ai)   │
│  └──────┬──────┘    or Backend.ONNX_AVX512 (x86 CPU)    │
│         │                                                │
│  ┌──────▼──────┐                                        │
│  │   ingest    │  VideoToolbox (M4) / ffmpeg (anywhere)  │
│  │  sampler    │  ARM NEON resize / AVX2 resize          │
│  └──────┬──────┘                                        │
│         │                                                │
│  ┌──────▼──────┐                                        │
│  │  detector   │  CoreML ANE (M4) / TensorRT (GPU)      │
│  │  (YOLOv8n)  │  / ONNX+AVX-512 (CPU)                 │
│  └──────┬──────┘                                        │
│         │                                                │
│  ┌──────▼──────┐                                        │
│  │ classifier  │  CoreML ANE / TensorRT / ONNX+AVX      │
│  │(EfficientB4)│  Tiered: T1(Jordo23) → T2(TypeNet)    │
│  └──────┬──────┘                                        │
│         │                                                │
│  ┌──────▼──────┐                                        │
│  │ deduplicator│  NEON popcount / AVX-512 VPOPCNTDQ     │
│  │  (pHash)    │  for hamming distance                   │
│  └──────┬──────┘                                        │
│         │                                                │
│  ┌──────▼──────┐                                        │
│  │   sanity    │  Pure Python (CPU-bound, fast enough)   │
│  │   check     │                                        │
│  └──────┬──────┘                                        │
│         │                                                │
│  ┌──────▼──────┐                                        │
│  │  persist    │  SQLite WAL (ARM NEON memcpy)           │
│  │  (db.py)    │                                        │
│  └─────────────┘                                        │
└─────────────────────────────────────────────────────────┘
```

---

## 9. Model Format Matrix

| Model | M4 Format | Vast.ai Format | Universal Fallback |
|-------|----------|----------------|-------------------|
| YOLOv8n (detect) | `.mlpackage` (INT8) | `.engine` (TensorRT FP16) | `.onnx` (FP32) |
| Jordo23 (classify) | `.mlpackage` (INT8) | `.engine` (TensorRT FP16) | `.onnx` (FP32) |
| VehicleTypeNet | `.mlpackage` (FP16) | `.onnx` (FP32, GPU) | `.onnx` (FP32) |
| Custom fine-tuned | `.mlpackage` (INT8) | `.engine` (TensorRT INT8) | `.onnx` (FP32) |

### Export Script (All Formats)

```bash
# scripts/export_all_formats.sh — Generate all model formats

MODEL_PATH="${1:?Usage: export_all_formats.sh <model.pt>}"

python3 -c "
from ultralytics import YOLO

model = YOLO('${MODEL_PATH}')

# CoreML for M4 Mac (ANE INT8 — fastest)
model.export(format='coreml', int8=True)

# ONNX for cross-platform (AVX-512/AVX2/NEON CPU)
model.export(format='onnx', dynamic=True, simplify=True)

# TensorRT for Vast.ai GPU (FP16)
try:
    model.export(format='engine', half=True, device=0)
except:
    print('TensorRT export skipped (no CUDA)')
"
```
