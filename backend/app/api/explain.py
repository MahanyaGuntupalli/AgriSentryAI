"""Module 9 endpoints - WHY? and WHAT TO DO?."""
from fastapi import APIRouter

from ..schemas.schemas import (DiseaseResult, EnvironmentalData, ExplanationResult,
                               RecommendationResult, RiskResult, WeatherData)
from ..services.explanation_service import build_explanation
from ..services.recommendation_service import build_recommendations

router = APIRouter(tags=["explain-recommend"])


class ExplainRequest(RiskResult):
    disease: DiseaseResult | None = None
    environmental_data: EnvironmentalData | None = None
    weather: WeatherData | None = None


class RecommendRequest(RiskResult):
    disease: DiseaseResult | None = None


@router.post("/api/explain")
def explain(req: ExplainRequest) -> dict:
    risk = RiskResult(level=req.level, score=req.score, factors=req.factors)
    result: ExplanationResult = build_explanation(risk, req.disease,
                                                  req.environmental_data, req.weather)
    return result.model_dump(mode="json")


@router.post("/api/recommend")
def recommend(req: RecommendRequest) -> dict:
    risk = RiskResult(level=req.level, score=req.score, factors=req.factors)
    result: RecommendationResult = build_recommendations(req.disease, risk)
    return result.model_dump(mode="json")