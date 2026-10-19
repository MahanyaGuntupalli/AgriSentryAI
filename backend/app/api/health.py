from fastapi import APIRouter

from ..services.disease_inference import disease_inference
from ..services.plant_inference import plant_inference

router = APIRouter(tags=["health"])


@router.get("/api/health")
def health() -> dict:
    """Liveness + AI deployment status.

    ``models`` tells integrators whether real inference is available. A NOT_
    DEPLOYED model must never be presented as TRAINED anywhere in the system.
    """
    return {
        "status": "ok",
        "models": {
            "crop_identification": plant_inference.status_report(),
            "disease": disease_inference.status_report(),
        },
    }
