"""Module 7 endpoint - standalone risk assessment (same engine /api/analyze uses)."""
from fastapi import APIRouter

from ..schemas.schemas import (CropInfo, DiseaseResult, RiskResult, SensorData,
                               WeatherData)
from ..services.risk_engine import assess_risk

router = APIRouter(tags=["risk"])


class RiskAssessmentRequest(SensorData):
    """Sensor fields + optional disease/weather/crop context in one body."""
    disease: DiseaseResult | None = None
    weather: WeatherData | None = None
    crop: CropInfo | None = None


@router.post("/api/risk/assess", response_model=None)
def assess(req: RiskAssessmentRequest) -> dict:
    sensor = SensorData(device_id=req.device_id, temperature=req.temperature,
                        humidity=req.humidity, soil_moisture=req.soil_moisture,
                        light=req.light, timestamp=req.timestamp,
                        leaf_wetness=req.leaf_wetness)
    result: RiskResult = assess_risk(disease=req.disease, env=sensor,
                                     weather=req.weather, crop=req.crop)
    return result.model_dump(mode="json")