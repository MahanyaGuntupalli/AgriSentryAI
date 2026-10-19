"""Image quality validation (Contract section 9; interface compatible with Module 3).

Checks performed before ANY image reaches the disease model:
  - minimum resolution
  - brightness (not too dark / too bright)
  - blur (Laplacian variance)

An unusable image is rejected with farmer-friendly reasons and is NEVER sent
to the disease model.
"""
from dataclasses import dataclass, field
from io import BytesIO
from typing import List

import numpy as np
from PIL import Image

MIN_RESOLUTION = 256
BRIGHTNESS_MIN = 45.0    # mean pixel value 0-255
BRIGHTNESS_MAX = 215.0
BLUR_THRESHOLD = 80.0    # variance of Laplacian; lower = blurrier


@dataclass
class QualityReport:
    accepted: bool
    reasons: List[str] = field(default_factory=list)
    brightness: float = 0.0
    blur_score: float = 0.0
    width: int = 0
    height: int = 0


def _laplacian_variance(gray: np.ndarray) -> float:
    lap = (
        -4.0 * gray[1:-1, 1:-1]
        + gray[:-2, 1:-1] + gray[2:, 1:-1]
        + gray[1:-1, :-2] + gray[1:-1, 2:]
    )
    return float(lap.var())


def check_image_quality(image_bytes: bytes) -> QualityReport:
    try:
        img = Image.open(BytesIO(image_bytes)).convert("RGB")
    except Exception:
        return QualityReport(False, ["The image file could not be read. Please retake the photo."])

    w, h = img.size
    gray = np.asarray(img.convert("L"), dtype=np.float64)
    brightness = float(gray.mean())
    blur = _laplacian_variance(gray)

    reasons: List[str] = []
    if w < MIN_RESOLUTION or h < MIN_RESOLUTION:
        reasons.append("Image is too small. Move closer and fill the frame with the leaf.")
    if brightness < BRIGHTNESS_MIN:
        reasons.append("Photo is too dark. Retake it in better daylight.")
    if brightness > BRIGHTNESS_MAX:
        reasons.append("Photo is too bright. Avoid direct glare on the leaf.")
    if blur < BLUR_THRESHOLD:
        reasons.append("Photo is blurry. Hold the phone steady and retake it.")

    return QualityReport(
        accepted=not reasons,
        reasons=reasons,
        brightness=round(brightness, 1),
        blur_score=round(blur, 1),
        width=w,
        height=h,
    )