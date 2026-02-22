import re
import json
import logging

logger = logging.getLogger(__name__)

def parse_parking_rules(ocr_text: str) -> dict:
    """
    Parses unstructured text extracted from Parking Signs into a 
    structured JSON-serializable rules dict.
    
    Example:
    OCR:
      2 HR PARKING
      8 AM TO 6 PM
      EXCEPT SUNDAYS
      
    Outputs:
      {
          "type": "time_limited",
          "duration_hours": 2,
          "start_time": "08:00",
          "end_time": "18:00",
          "exceptions": ["sunday"],
          "raw": "..."
      }
    """
    
    ocr_upper = ocr_text.upper()
    
    rules = {
        "type": "unknown",
        "duration_hours": None,
        "start_time": None,
        "end_time": None,
        "exceptions": [],
        "raw": ocr_text
    }
    
    # 1. Detect duration
    hr_match = re.search(r'(\d+)\s*(?:HR|HOUR)', ocr_upper)
    if hr_match:
        rules["duration_hours"] = int(hr_match.group(1))
        rules["type"] = "time_limited"
        
    min_match = re.search(r'(\d+)\s*(?:MIN|MINUTE)', ocr_upper)
    if min_match:
        rules["duration_hours"] = int(min_match.group(1)) / 60.0
        rules["type"] = "time_limited"

    # 2. Detect restrictions
    if "NO PARKING" in ocr_upper or "NO STOPPING" in ocr_upper:
        rules["type"] = "no_parking"
        
    if "PASSENGER" in ocr_upper or "LOADING" in ocr_upper:
        rules["type"] = "loading_zone"

    if "DISABLED" in ocr_upper or "HANDICAPPED" in ocr_upper:
        rules["type"] = "disabled"

    # 3. Detect time bounds (Naive regex capturing 8AM to 6PM type syntax)
    time_match = re.search(r'(\d+)(?::\d+)?\s*(AM|PM)?\s*(?:TO|-|THRU)\s*(\d+)(?::\d+)?\s*(AM|PM)', ocr_upper)
    if time_match:
        # e.g ("8", None, "6", "PM") or ("8", "AM", "6", "PM")
        s_val = time_match.group(1)
        s_ampm = time_match.group(2)
        e_val = time_match.group(3)
        e_ampm = time_match.group(4)
        
        # very simple standardizer assuming AM if missing from start and PM on end
        if not s_ampm:
            s_ampm = "AM" if int(s_val) >= 6 else "PM"
            
        def to_24(v, ap):
            v_int = int(v)
            if ap == "PM" and v_int != 12:
                v_int += 12
            if ap == "AM" and v_int == 12:
                v_int = 0
            return f"{v_int:02d}:00"
            
        rules["start_time"] = to_24(s_val, s_ampm)
        rules["end_time"] = to_24(e_val, e_ampm)

    # 4. Detect Exceptions
    days = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "HOLIDAY"]
    for d in days:
        if d in ocr_upper and ("EXCEPT" in ocr_upper or "NO LIMIT" in ocr_upper):
            rules["exceptions"].append(d.lower())
            
    return rules

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    test_str = "2 HR PARKING\n8 AM TO 6 PM\nEXCEPT SUNDAY"
    logger.info(f"Parsing OCR:\n{test_str}")
    parsed = parse_parking_rules(test_str)
    logger.info(json.dumps(parsed, indent=2))
