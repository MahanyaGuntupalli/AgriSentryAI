"""Module 8 - Future risk estimation (Contract section 18).

PROTOTYPE, RULE-BASED, CLEARLY LABELED. No trained predictive ML model is
claimed. The estimator projects the current risk score forward over 24/48/72h
using the weather trend and whether a disease is currently present.

  Disease persistence pressure : +4 per step (diseases do not disappear by themselves)
  Weather trend                : WORSENING +8 | STABLE 0 | IMPROVING -6 per step

The result carries model_type="PROTOTYPE_RULE_BASED" and an explicit
disclaimer so nobody mistakes the estimate for a guaranteed forecast.
"""
from typing import Optional

from ..schemas.schemas import (DiseaseResult, FutureRiskPoint, FutureRiskResult,
                               RiskLevel, RiskResult, WeatherData)

STEP_BY_TREND = {"WORSENING": 8, "STABLE": 0, "IMPROVING": -6}
DISEASE_STEP = 4
HORIZONS = ["CURRENT", "24H", "48H", "72H"]


def _level(score: int) -> RiskLevel:
    return RiskLevel.LOW if score < 40 else (RiskLevel.MEDIUM if score < 70 else RiskLevel.HIGH)


def _trend(delta: int) -> str:
    if delta > 4:
        return "WORSENING"
    if delta < -4:
        return "IMPROVING"
    return "STABLE"


def estimate_future_risk(
    current: RiskResult,
    weather: Optional[WeatherData] = None,
    disease: Optional[DiseaseResult] = None,
) -> FutureRiskResult:
    step = STEP_BY_TREND.get((weather.forecast_trend if weather else None) or "STABLE", 0)
    if disease and disease.status == "DISEASE_SUSPECTED":
        step += DISEASE_STEP

    points = []
    for i, horizon in enumerate(HORIZONS):
        score = max(0, min(100, current.score + step * i))
        points.append(FutureRiskPoint(
            horizon=horizon, level=_level(score), score=score,
            trend="STABLE" if i == 0 else _trend(step),
        ))
    return FutureRiskResult(points=points)