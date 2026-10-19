"""Module 8 endpoint - future risk estimate (PROTOTYPE_RULE_BASED, labeled)."""
from fastapi import APIRouter

from ..schemas.schemas import (DiseaseResult, FutureRiskResult, RiskResult,
                               WeatherData)
from ..services.future_risk_service import estimate_future_risk

router = APIRouter(tags=["future-risk"])


class FutureRiskRequest(RiskResult):
    weather: WeatherData | None = None
    disease: DiseaseResult | None = None


@router.post("/api/future-risk/estimate")
def estimate(req: FutureRiskRequest) -> dict:
    current = RiskResult(level=req.level, score=req.score, factors=req.factors)
    result: FutureRiskResult = estimate_future_risk(current, req.weather, req.disease)
    return result.model_dump(mode="json")