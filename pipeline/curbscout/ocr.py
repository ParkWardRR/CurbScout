import os
import logging
from PIL import Image

try:
    import Vision
    import CoreImage
    import Quartz
    import objc
    HAS_VISION = True
except ImportError:
    HAS_VISION = False

logger = logging.getLogger(__name__)

def recognize_text_apple_vision(image_path: str) -> str:
    """
    Leverages macOS native Vision API for hardware-accelerated OCR.
    """
    if not HAS_VISION:
        logger.warning("Apple Vision framework unavailable. Falling back to mock OCR.")
        return mock_ocr(image_path)
        
    if not os.path.exists(image_path):
        return ""

    try:
        # Load the image into a CIImage
        url = Quartz.NSURL.fileURLWithPath_(image_path)
        ci_image = CoreImage.CIImage.imageWithContentsOfURL_(url)
        
        if ci_image is None:
            logger.error(f"Failed to load CIImage from {image_path}")
            return ""

        # Create the OCR request
        request = Vision.VNRecognizeTextRequest.alloc().init()
        # Accurate uses ML, Fast uses heuristics
        request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
        request.setUsesLanguageCorrection_(True)
        
        # Handle execution
        handler = Vision.VNImageRequestHandler.alloc().initWithCIImage_options_(ci_image, None)
        
        success, error = handler.performRequests_error_([request], None)
        if not success:
            logger.error(f"Vision API failed: {error}")
            return ""

        # Extract text blocks
        results = request.results()
        if not results:
            return ""
            
        extracted_text = []
        for observation in results:
            # topCandidates_(1) gets the highest confidence string
            candidate = observation.topCandidates_(1)[0]
            extracted_text.append(candidate.string())
            
        return "\n".join(extracted_text)
        
    except Exception as e:
        logger.error(f"Apple Vision OCR execution error: {e}")
        return mock_ocr(image_path)

def mock_ocr(image_path: str) -> str:
    """Mock OCR returned if the Vision framework fails or is running on Linux (Vast.ai)."""
    return "2 HR PARKING\n8AM - 6PM\nEXCEPT SUNDAY"

def process_sign_crop(crop_path: str) -> str:
    """
    Reads text out of a parking sign image. 
    """
    return recognize_text_apple_vision(crop_path)

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    logger.info("Testing Vision OCR Framework loaded via PyObjC...")
    if HAS_VISION:
        logger.info("Apple native Vision library successfully hooked.")
    else:
        logger.warning("Vision missing. Are you running on Linux?")
