import logging
import json
import datetime
import importlib

class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "timestamp": datetime.datetime.fromtimestamp(record.created, tz=datetime.timezone.utc).isoformat(),
            "logger_name": record.name,
        }
        
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)

        # Standard GCP Cloud Logging structure
        return json.dumps(log_entry)

def setup_json_logging():
    """
    Overhauls the root logger to output structured JSON so GCP Cloud Logging 
    can ingest and parse parameters correctly from Cloud Run and Vast.ai outputs.
    """
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    
    root_logger = logging.getLogger()
    # Remove default handlers
    for h in root_logger.handlers[:]:
        root_logger.removeHandler(h)
        
    root_logger.addHandler(handler)
    root_logger.setLevel(logging.INFO)

if __name__ == "__main__":
    setup_json_logging()
    logger = logging.getLogger("Test.JSON")
    logger.info("JSON Structured logging initialized!")
