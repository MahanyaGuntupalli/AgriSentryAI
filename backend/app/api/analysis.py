"""Primary multimodal endpoint (Contract section 14-15): POST /api/analyze.

Multipart form:  file (leaf image), crop_name, device_id (optional).
The Flutter app does not need to know internal module details - one call
returns disease + risk + future risk + explanation + recommendation.
"""
from fastapi import APIRouter, File, Form, UploadFile

from ..services.analysis_service import run_analysis
from ..utils.errors import AppError

router = APIRouter(tags=["analysis"])


@router.post("/api/analyze")
async def analyze(file: UploadFile = File(...),
                  crop_name: str | None = Form(default=None),
                  device_id: str | None = Form(default=None),
                  user_id: str | None = Form(default=None)) -> dict:
    image_bytes = await file.read()
    if not image_bytes:
        raise AppError("EMPTY_IMAGE", "No image data was received.", 422)
    if len(image_bytes) > 15 * 1024 * 1024:
        raise AppError("IMAGE_TOO_LARGE", "Image is too large (max 15 MB).", 422)
    # crop_name is OPTIONAL farmer-provided metadata. It is never a default
    # assumption of "tomato" - identification comes from the crop model.
    return run_analysis(image_bytes, crop_name=crop_name,
                        device_id=device_id, user_id=user_id)