"""Module 7 - Environmental / multimodal risk engine (Contract section 17).

TRANSPARENT, DOCUMENTED RULE ENGINE - not a black box and not a claim of
scientific validation. Every weight and threshold is listed here so the team
can review, tune, and explain it.

Inputs:   disease result, sensor data, weather, crop info, recent history
Output:   RiskResult { level: LOW|MEDIUM|HIGH, score: 0-100, factors[] }

Scoring (each contribution capped, total clamped to 0..100):
  Disease indication  : 0..50   -> 25 + 25 * confidence when a disease is detected
  Humidity            : 0..20   -> >=85%: +20 | 70-84%: +12 | else 0
  Temperature         : 0..15   -> 20-30 C (fungal-favourable band): +15 | outside: +5
  Soil moisture       : 0..8    -> >80% (wet soil): +8 | <30% (plant stress): +4
  Leaf wetness        : 0..10   -> >=60%: +10  (optional sensor)
  Weather outlook     : 0..10   -> rain now / worsening trend: +10 | improving: 0
  Recent history      : 0..5    -> a HIGH risk scan in the last 7 days: +5

Thresholds: score < 40 -> LOW | 40-69 -> MEDIUM | >= 70 -> HIGH
"""
from typing import List, Optional

from ..schemas.schemas import (CropInfo, DiseaseResult, RiskLevel, RiskResult,
                               SensorData, WeatherData)

TEMP_FAVOURABLE_LO, TEMP_FAVOURABLE_HI = 20.0, 30.0


def assess_risk(
    disease: Optional[DiseaseResult] = None,
    env: Optional[SensorData] = None,
    weather: Optional[WeatherData] = None,
    crop: Optional[CropInfo] = None,
    history: Optional[List[dict]] = None,
) -> RiskResult:
    score = 0
    factors: List[str] = []

    # --- disease ---
    if disease and disease.status == "DISEASE_SUSPECTED":
        contribution = 25 + int(25 * disease.confidence)
        score += contribution
        factors.append(
            f"{disease.name} was detected on the leaf "
            f"({disease.confidence * 100:.0f}% confidence)."
        )

    # --- environment ---
    if env is not None:
        h = env.humidity
        if h >= 85:
            score += 20
            factors.append(f"Humidity is very high ({h:.0f}%).")
        elif h >= 70:
            score += 12
            factors.append(f"Humidity is high ({h:.0f}%).")

        t = env.temperature
        if TEMP_FAVOURABLE_LO <= t <= TEMP_FAVOURABLE_HI:
            score += 15
            factors.append(f"Temperature ({t:.0f}°C) favors disease development.")
        else:
            score += 5

        sm = env.soil_moisture
        if sm > 80:
            score += 8
            factors.append("Soil is very wet.")
        elif sm < 30:
            score += 4
            factors.append("Soil is dry; the plant is under stress.")

        if env.leaf_wetness is not None and env.leaf_wetness >= 60:
            score += 10
            factors.append("Leaves stayed wet for a long time.")

    # --- weather ---
    if weather is not None:
        if weather.rainfall and weather.rainfall > 0:
            score += 10
            factors.append("Rain was recorded recently.")
        elif weather.forecast_trend == "WORSENING":
            score += 10
            factors.append("The weather outlook is getting worse (more rain expected).")

    # --- history ---
    if history:
        recent_high = any(
            str(h.get("risk_level", "")).upper() == "HIGH" for h in history[:5]
        )
        if recent_high:
            score += 5
            factors.append("A recent scan already showed high risk.")

    score = max(0, min(100, score))
    level = RiskLevel.LOW if score < 40 else (RiskLevel.MEDIUM if score < 70 else RiskLevel.HIGH)
    if not factors:
        factors.append("Conditions look normal right now.")
    return RiskResult(level=level, score=score, factors=factors, engine="RULE_BASED_V1")