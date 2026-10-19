"""Disease inference - PLACEHOLDER implementation (Contract sections 10, 31).

The trained model is Module 4's responsibility. Until a trained model is
dropped in, this stub returns clearly-labeled SIMULATED results so the rest
of the pipeline (risk, prediction, explanation, recommendations, Flutter) can
be built and tested in parallel.

HOW TO SWAP IN THE REAL MODEL (Module 4):
  1. Train/save the model (e.g. a .keras / .tflite MobileNet into ai/models/).
  2. Set DISEASE_MODEL_PATH in backend/.env.
  3. Implement _predict_real() below with the same input/output contract:
       input : raw image bytes
       output: DiseaseResult(name=..., confidence=..., model_status="TRAINED")
  Nothing else in the backend or Flutter needs to change.

The placeholder NEVER reports model_status="TRAINED".
"""
import hashlib
import os
from pathlib import Path
from typing import Optional

from ..config import settings
from ..schemas.schemas import DiseaseCandidate, DiseaseResult

BASE_LABELS = ["Healthy", "Early Blight", "Late Blight", "Bacterial Spot"]
DISEASE_THRESHOLD = 0.80
HEALTHY_THRESHOLD = 0.65

# Disease classes that belong to other crops. When a trained model returns a
# class from this list while the Stage-1 crop identification says otherwise,
# the prediction is treated as a mismatch instead of a disease finding.
_CROP_CLASS_MARKERS = {
    "tomato": ("tomato",),
    "rice": ("rice", "blast", "brown spot", "hispa", "tungro"),
    "cotton": ("cotton", "bollworm", "army worm"),
    "chilli": ("chilli", "chili", "pepper"),
    "maize": ("maize", "corn", "rust, common"),
}


def _disease_class_matches_crop(label: str, crop_name: Optional[str]) -> bool:
    """True when the model class is consistent with the identified crop.

    Classes like 'Tomato ___ Late blight' or 'Rice blast' carry their crop in
    the name; crop-neutral classes (Healthy, Early Blight, ...) are accepted
    for any crop, exactly like the current 4-class model.
    """
    if not crop_name:
        return True
    low = label.strip().lower()
    for crop, markers in _CROP_CLASS_MARKERS.items():
        if any(marker in low for marker in markers) and crop != crop_name:
            return False
    return True


class DiseaseInference:
    def __init__(self, model_path: Optional[str] = None):
        project_root = Path(__file__).resolve().parents[3]
        default_model = project_root / "ai" / "models" / "tomato_disease_model.h5"
        self.model_path = model_path or settings.disease_model_path or str(default_model)
        self._model_cache = None  # loaded once, reused for every scan

    def status_report(self) -> dict:
        """Deployment status for /api/health - never imports TensorFlow."""
        if not self._real_model_available():
            return {"available": False, "status": "NOT_DEPLOYED",
                    "path": self.model_path}
        labels_path = Path(self.model_path).with_name("labels.txt")
        labels = ([line.strip() for line in labels_path.read_text().splitlines()
                   if line.strip()] if labels_path.is_file() else list(BASE_LABELS))
        return {"available": True, "status": "TRAINED",
                "path": self.model_path, "classes": labels}

    def _load_model(self):
        if self._model_cache is None:
            import tensorflow as tf
            self._model_cache = tf.keras.models.load_model(self.model_path)
        return self._model_cache

    def _real_model_available(self) -> bool:
        return os.path.isfile(self.model_path)

    def _predict_real(self, image_bytes: bytes,
                      crop_name: Optional[str] = None) -> DiseaseResult:
        """Run the trained model copied from the standalone AI module."""
        import numpy as np
        from PIL import Image
        from io import BytesIO

        image = Image.open(BytesIO(image_bytes)).convert("RGB").resize((224, 224))
        pixels = np.asarray(image, dtype=np.float32) / 255.0
        predictions = self._load_model().predict(
            np.expand_dims(pixels, axis=0), verbose=0
        )[0]

        labels_path = Path(self.model_path).with_name("labels.txt")
        if labels_path.is_file():
            labels = [line.strip() for line in labels_path.read_text().splitlines()
                      if line.strip()]
        else:
            labels = list(BASE_LABELS)
        if len(predictions) != len(labels):
            raise ValueError("The model output does not match the available labels.")
        order = np.argsort(predictions)[::-1]
        candidates = [
            DiseaseCandidate(name=labels[int(i)], confidence=round(float(predictions[i]), 4))
            for i in order[: min(5, len(order))]
        ]
        predicted_index = int(order[0])
        top_confidence = float(predictions[predicted_index])
        predicted_name = labels[predicted_index]

        # Crop-consistency gate: a class that names a DIFFERENT crop than the
        # one identified in Stage 1 is a mismatch, not a disease finding.
        if not _disease_class_matches_crop(predicted_name, crop_name):
            return DiseaseResult(
                name="No reliable disease detected",
                confidence=0.0,
                status="NO_RELIABLE_DISEASE",
                candidates=candidates,
                evidence=[
                    f"The top model class '{predicted_name}' belongs to a "
                    f"different crop than the identified crop "
                    f"('{crop_name}'), so it was not treated as a disease "
                    "finding."],
                model_status="TRAINED",
            )

        is_healthy = predicted_name.strip().lower() == "healthy"
        status = (
            "HEALTHY"
            if is_healthy and top_confidence >= HEALTHY_THRESHOLD
            else "DISEASE_SUSPECTED"
            if not is_healthy and top_confidence >= DISEASE_THRESHOLD
            else "NO_RELIABLE_DISEASE"
        )
        evidence = [] if status == "DISEASE_SUSPECTED" else [
            f"Top model class '{predicted_name}' at "
            f"{top_confidence * 100:.0f}% did not pass the "
            f"{DISEASE_THRESHOLD:.0%} disease-confidence threshold."]
        return DiseaseResult(
            name=predicted_name if status != "NO_RELIABLE_DISEASE" else "No reliable disease detected",
            # The top-level confidence always pairs with the CLAIM: when the
            # system refuses to name a disease it claims nothing, so it
            # reports 0. The full raw probability distribution remains
            # visible in `candidates` for transparency.
            confidence=round(top_confidence, 4)
            if status != "NO_RELIABLE_DISEASE" else 0.0,
            status=status,
            candidates=candidates,
            evidence=evidence,
            model_status="TRAINED",
        )

    def _predict_placeholder(self, image_bytes: bytes) -> DiseaseResult:
        """Deterministic pseudo-result from image hash - labeled SIMULATED."""
        digest = hashlib.sha256(image_bytes).digest()[0]
        return DiseaseResult(
            name="No reliable disease detected",
            confidence=0.0,
            status="NO_RELIABLE_DISEASE",
            candidates=[],
            evidence=["No trained disease model is available for this analysis."],
            model_status="PLACEHOLDER_SIMULATED",
        )

    def predict(self, image_bytes: bytes,
                crop_name: Optional[str] = None) -> DiseaseResult:
        """Run Stage-2 disease detection.

        ``crop_name`` is the crop identified from the image in Stage 1 (or the
        farmer's explicit selection when Stage 1 is unavailable). It scopes
        crop-specific model classes and the consistency gate - it is never a
        substitute for identification.
        """
        if self._real_model_available():
            try:
                return self._predict_real(image_bytes, crop_name=crop_name)
            except (ImportError, OSError, ValueError) as exc:
                # Keep the result honest: an unavailable or incompatible
                # model must never become a pseudo-disease prediction.
                return DiseaseResult(
                    name="Unable to determine from this image",
                    confidence=0.0,
                    status="UNAVAILABLE",
                    evidence=[f"Trained model could not be used: {exc}"],
                    model_status="PLACEHOLDER_SIMULATED",
                )
        return self._predict_placeholder(image_bytes)


disease_inference = DiseaseInference()