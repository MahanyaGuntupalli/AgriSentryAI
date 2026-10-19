"""Module 9a - farmer-facing crop-health investigation (Contract section 19).

Turns the risk factors, environment, weather, disease and history into a
structured, farmer-friendly diagnostic explanation. The result is advisory,
not a laboratory diagnosis.
"""
from typing import List, Optional

from ..schemas.schemas import (DiseaseResult, EnvironmentalData, ExplanationResult,
                               ExplanationSection, RiskResult, WeatherData)


def build_explanation(
    risk: RiskResult,
    disease: Optional[DiseaseResult] = None,
    env: Optional[EnvironmentalData] = None,
    weather: Optional[WeatherData] = None,
    history: Optional[List[dict]] = None,
    crop_name: str = "tomato",
) -> ExplanationResult:
    sections: List[ExplanationSection] = []

    plant_part = "leaf"
    if disease:
        if disease.status == "HEALTHY":
            what = "The leaf looks healthy."
        elif disease.status == "DISEASE_SUSPECTED":
            what = f"The leaf shows signs of {disease.name}."
        else:
            what = "No reliable disease was detected from the available image evidence."
        sections.append(ExplanationSection(
            title="Observed", icon="leaf",
            body=f"Crop: {crop_name}. Plant part: {plant_part}. {what}"))
        sections.append(ExplanationSection(
            title="Inferred", icon="search",
            body=(
                f"The most likely problem is {disease.name}. "
                f"The available model confidence is {disease.confidence * 100:.0f}%, "
                "but confidence is not proof of disease."
            ) if disease.status == "DISEASE_SUSPECTED" else (
                "The available evidence is not strong enough to name a disease. "
                "Environmental conditions can increase future risk, but they do "
                "not prove that a disease is present."
            )))

        if disease.status in {"HEALTHY", "NO_RELIABLE_DISEASE"}:
            alternatives = (
                "No clear disease indication was returned. Minor nutrient stress, "
                "water stress, pest damage or early symptoms may still be missed "
                "if they are not visible in the image."
            )
        else:
            alternatives = (
                "Other possibilities include nutrient deficiency, water stress, "
                "pest damage or a bacterial/viral problem. A single image cannot "
                "reliably distinguish every similar-looking cause."
            )
        sections.append(ExplanationSection(
            title="Possible alternatives", icon="compare",
            body=alternatives))

    if env:
        sections.append(ExplanationSection(
            title="Supported by context", icon="thermometer",
            body=(f"Temperature is {env.temperature:.0f}°C, humidity {env.humidity:.0f}% "
                  f"and soil moisture {env.soil_moisture:.0f}%. "
                  + ("These wet, warm conditions help disease spread."
                     if env.humidity >= 70 else "These conditions are within a normal range."))))

    if weather:
        outlook = {
            "WORSENING": "Rain is expected soon, which can increase the risk.",
            "IMPROVING": "The weather is expected to improve.",
            "STABLE": "The weather is expected to stay stable.",
        }.get(weather.forecast_trend or "STABLE", "The weather is expected to stay stable.")
        sections.append(ExplanationSection(
            title="Environmental connection", icon="cloud",
            body=f"Right now: {weather.condition or 'unknown'}, {weather.temperature:.0f}°C. {outlook}"
                 if weather.temperature is not None else outlook))

    if history:
        high = sum(1 for h in history if str(h.get("risk_level", "")).upper() == "HIGH")
        if high:
            sections.append(ExplanationSection(
                title="History", icon="clock",
                body=f"{high} recent scan(s) already showed high risk. The problem may be growing."))

    evidence = " ".join(risk.factors[:5])
    sections.append(ExplanationSection(
        title="Why this risk", icon="info",
        body=(
            f"The risk score is {risk.score}/100 ({risk.level.value}). "
            f"Supporting context: {evidence}"
            if evidence else
            f"The risk score is {risk.score}/100 ({risk.level.value}); "
            "there is limited supporting context."
        )))

    if risk.level.value in {"HIGH", "MEDIUM"}:
        severity = (
            f"{risk.level.value}: the rule-based score is {risk.score}/100. "
            "This reflects the detected indication and supporting conditions, "
            "not a measured percentage of damaged plant tissue or predicted yield loss."
        )
        risk_body = (
            "If the problem progresses, affected leaves may decline and the "
            "risk may spread to more of the crop. The score is an estimate, "
            "not a guaranteed yield-loss forecast."
        )
        immediate = (
            "Inspect the affected leaves and the surrounding plants today. "
            "Remove severely affected material with clean tools, avoid spreading "
            "debris, and avoid wetting the foliage."
        )
    else:
        severity = (
            f"{risk.level.value}: the rule-based score is {risk.score}/100. "
            "Visible damage extent and future yield impact cannot be estimated "
            "reliably from the available evidence."
        )
        risk_body = (
            "Current conditions do not indicate a high immediate risk, but early "
            "symptoms can change. Continue routine inspection."
        )
        immediate = (
            "Inspect several representative leaves today and keep a clear photo "
            "record so changes can be compared."
        )
    sections.extend([
        ExplanationSection(
            title="Severity assessment", icon="assessment", body=severity),
        ExplanationSection(title="Risk", icon="warning", body=risk_body),
        ExplanationSection(title="What to do now", icon="check", body=immediate),
        ExplanationSection(
            title="Treatment and management", icon="build",
            body=(
                "Use integrated management first: sanitation, removal of severely "
                "affected material when appropriate, base watering, drainage and "
                "airflow. Do not apply a pesticide from this result alone. If "
                "chemical treatment is considered, confirm the diagnosis and use "
                "only a locally approved product exactly according to its label "
                "and local agricultural advice."
            )),
        ExplanationSection(
            title="Next 3-7 days", icon="calendar",
            body=(
                "Recheck the crop every day when risk is high, or every 2-3 days "
                "when risk is medium. Compare new spots, spread and wilting with "
                "the previous scan."
            )),
        ExplanationSection(
            title="Prevention", icon="shield",
            body=(
                "Keep foliage as dry as practical, water at the plant base, "
                "maintain air circulation, remove weeds and plant debris, and "
                "avoid working through wet plants. Follow locally approved crop "
                "guidance before using any chemical treatment."
            )),
        ExplanationSection(
            title="What to monitor", icon="eye",
            body=(
                "Look for new or enlarging spots, yellowing, browning, curling, "
                "wilting, visible insects, faster spread after rain, and symptoms "
                "appearing on nearby plants."
            )),
        ExplanationSection(
            title="When to contact an expert", icon="person",
            body=(
                "Ask an agricultural officer or plant specialist to confirm the "
                "diagnosis if confidence is low, symptoms spread quickly, much "
                "of the crop is affected, or a pesticide decision is needed."
            )),
        ExplanationSection(
            title="Uncertain", icon="help",
            body=(
                "Image quality, plant age, location, soil condition, recent "
                "treatments and laboratory confirmation may be unavailable. "
                "This result combines the available model indication, sensor "
                "context, weather and history; it is not a laboratory diagnosis."
            )),
    ])

    level_word = risk.level.value.lower()
    factor_text = " ".join(risk.factors[:3])
    summary = (f"Your crop is at {level_word} risk ({risk.score}/100). Main reasons: {factor_text}"
               if risk.factors else f"Your crop is at {level_word} risk ({risk.score}/100).")

    return ExplanationResult(
        summary=summary, sections=sections,
        confidence=disease.confidence if disease else None,
    )