"""Plant / crop identification - STAGE 1 of the image-analysis pipeline.

This module exists because database records of crops do NOT give the AI the
ability to recognize them: crop identification must come from a trained
vision model looking at the image itself.

Design (mirrors disease_inference.py):
  - If a trained crop model is deployed (default search path:
    ``ai/models/crop_model.h5`` next to the backend, or ``CROP_MODEL_PATH``),
    real predictions are returned with ``status="IDENTIFIED"``.
  - If the model is missing, unloadable, or its output is below threshold,
    the result is explicitly ``UNCERTAIN`` / ``UNKNOWN`` / ``UNAVAILABLE``.
    A crop name is NEVER fabricated and the user-selected crop is NEVER
    silently accepted as an identification.

Consistency gate (when the farmer also selected a crop in the app):
  - identified == requested          -> ``status="IDENTIFIED"``
  - identified != requested, model sure  -> ``MISMATCH_REQUESTED_CROP``
  - identified != requested, model unsure-> ``UNCERTAIN`` + evidence note
  - nothing identified               -> ``UNKNOWN``

The model's class order is read from ``crop_model_labels.txt`` (one class per
line, index-aligned with the model's softmax output). Classes are matched
case-insensitively; include an ``Unknown``/``Not a plant`` class in training
so non-crop photos can be rejected.
"""
import os
from pathlib import Path
from typing import List, Optional, Tuple

from ..config import settings
from ..schemas.schemas import CropInfo, PlantCandidate, PlantIdentification

# Canonical classes this system is designed for. The deployed model may have
# its own list - the labels file always wins when present.
CANONICAL_CLASSES = ["Cotton", "Maize", "Rice", "Tomato", "Chilli"]

# app crop ids -> canonical class names
_CROP_ALIASES = {
    "tomato": "Tomato",
    "rice": "Rice",
    "cotton": "Cotton",
    "chilli": "Chilli",
    "chili": "Chilli",
    "maize": "Maize",
    "corn": "Maize",
}

# Class-name fragments treated as "no crop on this image".
_NEGATIVE_CLASS_MARKERS = ("unknown", "not a plant", "background", "other")


class PlantInference:
    def __init__(self, model_path: Optional[str] = None):
        project_root = Path(__file__).resolve().parents[3]
        default_model = project_root / "ai" / "models" / "crop_model.h5"
        self.model_path = model_path or settings.crop_model_path or str(default_model)
        self._model_cache = None  # loaded once, reused for every scan

    # ---------------- model availability ----------------

    def _labels_path(self) -> Path:
        return Path(self.model_path).with_name("crop_model_labels.txt")

    def _load_labels(self) -> List[str]:
        path = self._labels_path()
        if path.is_file():
            labels = [line.strip() for line in
                      path.read_text(encoding="utf-8").splitlines() if line.strip()]
            if labels:
                return labels
        return list(CANONICAL_CLASSES)

    def _real_model_available(self) -> bool:
        return os.path.isfile(self.model_path)

    def _load_model(self):
        if self._model_cache is None:
            import tensorflow as tf  # heavy import - deferred until needed
            self._model_cache = tf.keras.models.load_model(self.model_path)
        return self._model_cache

    def status_report(self) -> dict:
        """Deployment status for /api/health - never imports TensorFlow."""
        if not self._real_model_available():
            return {"available": False, "status": "NOT_DEPLOYED",
                    "path": self.model_path}
        return {"available": True, "status": "TRAINED",
                "path": self.model_path, "classes": self._load_labels()}

    # ---------------- matching helpers ----------------

    @staticmethod
    def _is_negative(label: str) -> bool:
        low = label.strip().lower()
        return any(marker in low for marker in _NEGATIVE_CLASS_MARKERS)

    @staticmethod
    def _canonical(label: str) -> Optional[str]:
        low = label.strip().lower()
        for canonical in CANONICAL_CLASSES:
            if canonical.lower() == low:
                return canonical
        for canonical in CANONICAL_CLASSES:
            if canonical.lower() in low:
                return canonical
        return None

    def _requested_canonical(self, requested_crop: Optional[str]) -> Optional[str]:
        if not requested_crop:
            return None
        return _CROP_ALIASES.get(str(requested_crop).strip().lower())

    # ---------------- inference ----------------

    def _predict_real(self, image_bytes: bytes) -> PlantIdentification:
        import numpy as np
        from io import BytesIO
        from PIL import Image

        image = Image.open(BytesIO(image_bytes)).convert("RGB").resize((224, 224))
        pixels = np.asarray(image, dtype=np.float32) / 255.0
        predictions = self._load_model().predict(
            np.expand_dims(pixels, axis=0), verbose=0)[0]

        labels = self._load_labels()
        if len(predictions) != len(labels):
            raise ValueError(
                "Crop model output size does not match the label list.")

        order = np.argsort(predictions)[::-1]
        candidates = [
            PlantCandidate(name=labels[int(i)],
                           confidence=round(float(predictions[i]), 4))
            for i in order[: min(3, len(order))]
        ]
        top_name = labels[int(order[0])]
        top_conf = float(predictions[int(order[0])])

        evidence: List[str] = [
            f"Top match '{top_name}' at {top_conf * 100:.0f}% confidence."]

        # "Unknown / not a plant" class wins -> nothing to identify.
        if self._is_negative(top_name) and \
                top_conf >= settings.crop_id_threshold:
            return PlantIdentification(
                name=top_name, confidence=round(top_conf, 4),
                candidates=candidates, status="UNKNOWN", evidence=evidence)

        if top_conf < settings.crop_id_threshold:
            return PlantIdentification(
                name=top_name, confidence=round(top_conf, 4),
                candidates=candidates, status="UNCERTAIN",
                evidence=evidence + [
                    "Confidence is below the identification threshold, "
                    "so no crop is claimed."])

        canonical = self._canonical(top_name)
        if canonical is None:
            return PlantIdentification(
                name=top_name, confidence=round(top_conf, 4),
                candidates=candidates, status="UNCERTAIN",
                evidence=evidence + [
                    "The identified class is not one of the supported crops."])

        return PlantIdentification(
            name=canonical, confidence=round(top_conf, 4),
            candidates=candidates, status="IDENTIFIED", evidence=evidence)

    def _predict_placeholder(self, image_bytes: bytes) -> PlantIdentification:
        """No trained crop model deployed - explicitly unknown, never faked."""
        return PlantIdentification(
            name="Unknown Plant",
            confidence=0.0,
            candidates=[],
            status="UNKNOWN",
            evidence=["No trained crop-identification model is deployed, "
                      "so the crop cannot be determined from this image."])

    def identify(
        self, image_bytes: bytes, requested_crop: Optional[str] = None
    ) -> Tuple[PlantIdentification, CropInfo]:
        """Identify the crop in the image and build the request's CropInfo.

        Returns (plant, crop). When the farmer's selected crop conflicts with
        a confident identification, ``plant.status`` is
        ``MISMATCH_REQUESTED_CROP`` and ``crop.crop_name`` keeps the
        identified crop for downstream per-crop logic.
        """
        if self._real_model_available():
            try:
                plant = self._predict_real(image_bytes)
            except (ImportError, OSError, ValueError) as exc:
                plant = PlantIdentification(
                    name="Unknown Plant", confidence=0.0, status="UNAVAILABLE",
                    evidence=[f"Crop model could not be used: {exc}"])
        else:
            plant = self._predict_placeholder(image_bytes)

        requested = self._requested_canonical(requested_crop)
        if requested is not None and plant.status == "IDENTIFIED":
            if plant.name != requested:
                if plant.confidence >= settings.crop_conflict_threshold:
                    plant.status = "MISMATCH_REQUESTED_CROP"
                    plant.evidence = list(plant.evidence) + [
                        f"Selected crop '{requested}' does not match the "
                        f"crop identified in the image ('{plant.name}'). "
                        "The image analysis continues with the identified "
                        "crop."]
                else:
                    plant.status = "UNCERTAIN"
                    plant.evidence = list(plant.evidence) + [
                        "The identification disagrees with the selected crop "
                        "but is not confident enough to override it."]
                # Keep the identified name visible; the analysis continues
                # with the crop the model actually saw.
            crop = CropInfo(crop_name=plant.name)
        else:
            # No confident identification: the farmer's explicit selection is
            # used ONLY as request metadata, never reported as an
            # identification. Unknown selections are recorded as such.
            crop = CropInfo(crop_name=requested_crop if requested else "unknown")
            if requested_crop and requested is None:
                plant.evidence = list(plant.evidence) + [
                    f"Selected crop '{requested_crop}' is not a recognized "
                    "crop for this system."]
        return plant, crop


plant_inference = PlantInference()
