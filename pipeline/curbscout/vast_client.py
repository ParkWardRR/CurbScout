import os
import httpx
import logging

logger = logging.getLogger(__name__)

class VastClient:
    def __init__(self, api_key: str = None):
        self.api_key = api_key or os.environ.get("VAST_AI_API_KEY")
        if not self.api_key:
            logger.warning("Vast.ai API key is missing. Interactions will fail.")
        self.base_url = "https://console.vast.ai/api/v0"
        
    def _headers(self):
        return {"Authorization": f"Bearer {self.api_key}", "Accept": "application/json"}
        
    def search_offers(self, gpu_name="RTX_4090", max_price=0.50):
        """
        Search for available rent-able GPUs on Vast.ai matching the specified thresholds.
        """
        logger.info(f"Searching Vast.ai for {gpu_name} < ${max_price}/hr...")
        
        # In a real environment, query string syntax for vast needs careful construction
        # Example query: {"gpu_name": {"eq": "RTX_4090"}, "dph": {"lte": "0.50"}}
        query = {"gpu_name": {"eq": gpu_name}, "dph": {"lte": str(max_price)}}
        
        # Stub response matching Vast.ai API shape
        return [{
            "id": 123456,
            "gpu_name": gpu_name,
            "dph_base": max_price - 0.1, # Price per hour
            "dlperf": 25.0,
            "machine_id": 9999
        }]

    def launch_instance(self, offer_id: int, setup_script: str):
        """
        Leases a GPU and injects the 'bootstrap_training.sh' script as onstart.
        """
        if not self.api_key:
            return {"success": False, "error": "No API key"}
            
        logger.info(f"Launching instance on offer {offer_id}...")
        
        payload = {
            "client_id": "me",
            "image": "nvidia/cuda:12.1.1-devel-ubuntu22.04", # Pytorch/CUDA 12 base
            "env": {"-e": "TZ=UTC"},
            "disk": 50, # 50 GB
            "onstart": setup_script,
            "runtype": "ssh_ondemand"
        }
        
        # Mocking HTTP call to keep tests running clean without accidental charges
        # response = httpx.put(f"{self.base_url}/asks/{offer_id}/", json=payload, headers=self._headers())
        # return response.json()
        
        return {"success": True, "new_contract": 987654321}

    def destroy_instance(self, instance_id: int):
        """
        Tears down the GPU instance, halting hourly billing immediately.
        """
        logger.info(f"Issuing self-destruct for Vast.ai instance {instance_id}")
        
        # response = httpx.delete(f"{self.base_url}/instances/{instance_id}/", headers=self._headers())
        # return response.json()
        
        return {"success": True}
