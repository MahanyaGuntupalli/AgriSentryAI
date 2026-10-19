"""Full multimodal analysis pipeline - wires Modules 3,4,6,7,8,9 together.

Pipeline (Master Specification section 25):
  image -> quality check -> disease AI -> +environment -> +weather
        -> risk engine -> future risk -> explanation -> recommendations
        -> store history -> return the contract-shaped response of section 15.
"""
from typing import Optional

from ..database.db import db
from ..schemas.schemas import (CropInfo, DiseaseResult, EnvironmentalData,
                               ExplanationResult, FutureRiskResult,
                               ImageQualityResult, PlantIdentification,
                               RecommendationResult, RiskResult, WeatherData)
from ..utils.errors import AppError
from ..utils.image_quality import check_image_quality
from .disease_inference import disease_inference
from .explanation_service import build_explanation
from .future_risk_service import estimate_future_risk
from .plant_inference import plant_inference
from .recommendation_service import build_recommendations
from .risk_engine import assess_risk
from .weather_service import weather_service


def run_analysis(image_bytes: bytes, crop_name: Optional[str] = None,
                 device_id: Optional[str] = None,
                 user_id: Optional[str] = None) -> dict:
    # 1. Image quality gate - unusable images never reach any model.
    report = check_image_quality(image_bytes)
    if not report.accepted:
        raise AppError("IMAGE_QUALITY_REJECTED", " ".join(report.reasons), 422)

    # 2. Latest environmental reading for this device (SIMULATED or REAL).
    env_row = db.latest_sensor(device_id) if device_id else db.latest_sensor()
    env = EnvironmentalData(**env_row) if env_row else None

    # 3. Weather context (never hard-coded as real; provider labels itself).
    try:
        weather: Optional[WeatherData] = weather_service.get_current()
    except AppError:
        weather = None   # graceful degradation - analysis continues without weather

    # 4. STAGE 1 - crop identification from the image itself (when a trained
    #    crop model is deployed). The farmer's selected crop is request
    #    metadata, never presented as an identification.
    plant, crop = plant_inference.identify(image_bytes, requested_crop=crop_name)

    # 5. STAGE 2 - disease detection (TRAINED model or clearly labeled
    #    placeholder), run with the crop context from Stage 1.
    disease: DiseaseResult = disease_inference.predict(image_bytes,
                                                       crop_name=crop.crop_name)

    # 6. Risk + future risk + explanation + recommendations.
    recent = db.history(limit=5)
    risk: RiskResult = assess_risk(disease=disease, env=env, weather=weather,
                                   crop=crop, history=recent)
    future: FutureRiskResult = estimate_future_risk(risk, weather, disease)
    explanation: ExplanationResult = build_explanation(
        risk, disease, env, weather, recent,
        crop_name=crop.crop_name or "unknown")
    recommendations: RecommendationResult = build_recommendations(disease, risk)

    # 7. Persist to history (Contract section 22).
    scan_id = db.insert_scan({
        "user_id": user_id, "crop_name": crop_name, "device_id": device_id,
        "disease_name": disease.name, "confidence": disease.confidence,
        "model_status": disease.model_status,
        "plant_name": plant.name,
        "plant_confidence": plant.confidence,
        "plant_status": plant.status,
        "disease_status": disease.status,
        "disease_candidates": [c.model_dump(mode="json") for c in disease.candidates],
        "image_quality": report.__dict__,
        "model_version": disease.model_status,
        "risk_level": risk.level.value, "risk_score": risk.score,
        "risk_factors": risk.factors,
        "future_risk": future.model_dump(mode="json"),
        "explanation": explanation.model_dump(mode="json"),
        "recommendations": recommendations.model_dump(mode="json"),
    })

    # 8. Contract-shaped response (Contract section 15).
    return {
        "scan_id": scan_id,
        "disease": disease.model_dump(mode="json"),
        "plant": plant.model_dump(mode="json"),
        "risk": risk.model_dump(mode="json"),
        "future_risk": future.model_dump(mode="json"),
        "explanation": explanation.model_dump(mode="json"),
        "recommendation": recommendations.model_dump(mode="json"),
        "environmental_data": env.model_dump(mode="json") if env else None,
        "weather": weather.model_dump(mode="json") if weather else None,
        "image_quality": ImageQualityResult(
            accepted=report.accepted,
            status="ACCEPTED" if report.accepted else "INSUFFICIENT",
            reasons=report.reasons,
            brightness=report.brightness,
            blur_score=report.blur_score,
            width=report.width,
            height=report.height,
        ).model_dump(mode="json"),
    }