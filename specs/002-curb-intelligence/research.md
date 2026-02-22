# Research: Curb Intelligence

## Decisions

### 1. Parking Sign Detection & OCR

- **Decision**: Train a new YOLOv8 object detector specifically for the "Parking Sign" class, then crop and pass the signs to PaddleOCR or Apple Vision framework (native OCR) via CoreML.
- **Rationale**: The M4 Mac mini ANE accelerates CoreML natively. Apple's Vision framework `VNRecognizeTextRequest` is built-in to macOS, extremely fast on Apple Silicon, and requires zero extra Python heavy weights compared to PaddleOCR. We will use Apple Native Vision OCR via a Swift/PyObjC bridge or simply deploy PaddleOCR in ONNX format if pure Python is strongly desired. Given the emphasis on "Apple-level integration," `VNRecognizeTextRequest` is preferred because it's native and free.
- **Alternatives considered**: PaddleOCR (heavy dependencies), Tesseract (too slow/inaccurate).

### 2. Hazard Mapping

- **Decision**: Fine-tune YOLOv8 to detect `bike_lane_obstruction`, `pothole`, and `construction_cone`.
- **Rationale**: Hazards can be treated exactly like vehicles. The existing `detector.py` can load a secondary `yolov8n-hazards.pt` model explicitly tracking these classes. 
- **Alternatives considered**: Separate models per hazard (too slow). Semantic segmentation (too resource intensive for 2fps extraction).

### 3. Parse Rules from Text

- **Decision**: Feed raw OCR text to a local LLM or rule-based parser for structured extraction. 
- **Rationale**: Given OCR text, parsing things like "2 HR PARKING" can be done reliably with Regex rules for MVP, avoiding the need for heavy LLMs on the ingestion node.

## Conclusion
The architecture cleanly aligns with the existing `detector.py` script. We just need to load standard ML models for new tasks.
