import logging
import platform
import os
from enum import Enum, auto

logger = logging.getLogger(__name__)

class Backend(Enum):
    COREML_ANE = auto()        # Apple Neural Engine (M1-M4)
    COREML_GPU = auto()        # Apple Silicon GPU
    CUDA_TENSORRT = auto()     # NVIDIA with TensorRT
    CUDA = auto()              # NVIDIA basic CUDA
    ONNX_AVX512 = auto()       # Intel AVX-512
    ONNX_NEON = auto()         # ARM NEON (CPU fallback)
    CPU = auto()               # Generic CPU

def detect_best_backend() -> Backend:
    """
    Detects the best available hardware accelerator.
    For the M4 Mac mini, this will return COREML_ANE.
    For Vast.ai instances, this returns CUDA_TENSORRT or CUDA.
    """
    # Detect Apple Silicon (CoreML)
    if platform.system() == "Darwin" and platform.machine() == "arm64":
        return Backend.COREML_ANE

    # Detect CUDA
    # Typically we'd check `torch.cuda.is_available()` but we might not want standard torch dependency.
    # We can check nvcc or ONNX Providers.
    try:
        import onnxruntime as ort
        providers = ort.get_available_providers()
        if 'TensorrtExecutionProvider' in providers:
            return Backend.CUDA_TENSORRT
        elif 'CUDAExecutionProvider' in providers:
            return Backend.CUDA
    except ImportError:
        pass
        
    # Simplified x86 fallback
    if platform.machine() in ["x86_64", "AMD64"]:
        return Backend.ONNX_AVX512
        
    return Backend.CPU

def load_coreml_model(model_path: str, force_ane: bool = True):
    """
    Loads a CoreML model using coremltools, explicitly targeting the Neural Engine
    to save CPU/GPU cycles for other pipeline tasks.
    """
    try:
        import coremltools as ct
        compute_units = ct.ComputeUnit.CPU_AND_NE if force_ane else ct.ComputeUnit.ALL
        
        logger.info(f"Loading CoreML model {model_path} with {compute_units.name}")
        model = ct.models.MLModel(model_path, compute_units=compute_units)
        return model
    except ImportError:
        logger.warning("coremltools not installed, cannot load CoreML format.")
        return None
    except Exception as e:
        logger.error(f"Failed to load CoreML model: {e}")
        raise

def create_onnx_session(model_path: str, backend: Backend):
    """
    Fallback for classification networks not yet compiled to CoreML,
    or for Vast.ai execution.
    """
    import onnxruntime as ort
    
    sess_options = ort.SessionOptions()
    sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    
    providers = ['CPUExecutionProvider']
    
    if backend in (Backend.CUDA, Backend.CUDA_TENSORRT):
        # Configure TensorRT provider if possible
        if backend == Backend.CUDA_TENSORRT:
            providers = ['TensorrtExecutionProvider', 'CUDAExecutionProvider', 'CPUExecutionProvider']
        else:
            providers = ['CUDAExecutionProvider', 'CPUExecutionProvider']
            
    # For Apple Silicon ONNX inference, CoreMLExecutionProvider is available
    if backend in (Backend.COREML_ANE, Backend.COREML_GPU):
        providers = ['CoreMLExecutionProvider', 'CPUExecutionProvider']

    logger.info(f"Creating ONNX session with providers {providers}")
    return ort.InferenceSession(model_path, sess_options, providers=providers)
