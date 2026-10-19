"""Shared request/response schemas (Contract sections 11, 15, 17, 18, 19, 20, 22).

JSON field names here are the official contract names - do not rename.
"""
from datetime import datetime
from enum import Enum
from typing import List, Optional

from pydantic import BaseModel, Field


# ---------- Enums ----------

class RiskLevel(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"


class Urgency(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


# ---------- Environmental / Sensor (Contract sections 11-13) ----------

class SensorData(BaseModel):
    device_id: str = Field(..., examples=["ESP32_001"])
    temperature: float      # degrees Celsius
    humidity: float         # percentage
    soil_moisture: float    # normalized percentage (see calibration docs)
    light: float            # sensor-dependent value (LDR raw)
    timestamp: Optional[datetime] = None   # ISO-8601; server fills if omitted
    leaf_wetness: Optional[float] = None   # optional
    source: Optional[str] = None           # "REAL" | "SIMULATED" (derived from device_id)


class EnvironmentalData(SensorData):
    """Same contract object, used when the backend returns a stored reading."""
    timestamp: datetime
    source: str = "SIMULATED"


# ---------- Weather (Contract section 16) ----------

class WeatherData(BaseModel):
    temperature: Optional[float] = None
    humidity: Optional[float] = None
    rainfall: Optional[float] = None        # mm (forecast probability where only that exists)
    condition: Optional[str] = None         # e.g. "Rain", "Clear", "Clouds"
    forecast_trend: Optional[str] = None    # "IMPROVING" | "STABLE" | "WORSENING"
    timestamp: datetime
    source: str = "SIMULATED"               # "REAL" | "SIMULATED" - never mislabel


# ---------- Disease (Contract section 10) ----------

class DiseaseResult(BaseModel):
    name: str
    confidence: float = Field(..., ge=0.0, le=1.0)
    # TRAINED = validated model output; PLACEHOLDER_SIMULATED = development stub.
    # The API never presents a placeholder as a production model.
    model_status: str = "PLACEHOLDER_SIMULATED"
    status: str = "NO_RELIABLE_DISEASE"
    candidates: List["DiseaseCandidate"] = []
    evidence: List[str] = []


class DiseaseCandidate(BaseModel):
    name: str
    confidence: float = Field(..., ge=0.0, le=1.0)


class PlantCandidate(BaseModel):
    name: str
    confidence: float = Field(..., ge=0.0, le=1.0)


class PlantIdentification(BaseModel):
    name: str = "Unknown Plant"
    confidence: float = Field(0.0, ge=0.0, le=1.0)
    candidates: List[PlantCandidate] = []
    # IDENTIFIED = model identified this crop. UNCERTAIN / UNKNOWN /
    # UNAVAILABLE / MISMATCH_REQUESTED_CROP = never presented as an ID.
    status: str = "UNAVAILABLE"
    evidence: List[str] = []


class ImageQualityResult(BaseModel):
    accepted: bool
    status: str
    reasons: List[str] = []
    brightness: float = 0.0
    blur_score: float = 0.0
    width: int = 0
    height: int = 0


class CropInfo(BaseModel):
    crop_name: str = "tomato"
    growth_stage: Optional[str] = None
    location: Optional[str] = None


# ---------- Risk (Contract section 17) ----------

class RiskResult(BaseModel):
    level: RiskLevel
    score: int = Field(..., ge=0, le=100)
    factors: List[str] = []     # farmer-friendly contributing factors
    engine: str = "RULE_BASED_V1"   # transparent rule engine, documented in risk_engine.py


# ---------- Future risk (Contract section 18) ----------

class FutureRiskPoint(BaseModel):
    horizon: str                # "CURRENT" | "24H" | "48H" | "72H"
    level: RiskLevel
    score: int = Field(..., ge=0, le=100)
    trend: str = "STABLE"       # "IMPROVING" | "STABLE" | "WORSENING"


class FutureRiskResult(BaseModel):
    points: List[FutureRiskPoint]
    model_type: str = "PROTOTYPE_RULE_BASED"
    disclaimer: str = (
        "This is an estimate based on current conditions and weather trends, "
        "not a guaranteed forecast."
    )


# ---------- Explanation (Contract section 19) ----------

class ExplanationSection(BaseModel):
    title: str                  # e.g. "What we saw", "Environment", "Weather"
    body: str
    icon: Optional[str] = None  # UI hint, e.g. "leaf", "droplet", "cloud"


class ExplanationResult(BaseModel):
    summary: str
    sections: List[ExplanationSection] = []
    confidence: Optional[float] = None   # AI confidence where applicable


# ---------- Recommendations (Contract section 20) ----------

class RecommendationItem(BaseModel):
    title: str
    detail: str
    urgency: Urgency = Urgency.MEDIUM


class RecommendationCategory(BaseModel):
    do_now: List[RecommendationItem] = []
    manage: List[RecommendationItem] = []
    prevent: List[RecommendationItem] = []
    monitor: List[RecommendationItem] = []
    water: List[RecommendationItem] = []
    environment: List[RecommendationItem] = []


class RecommendationResult(BaseModel):
    categories: RecommendationCategory
    disclaimer: str = (
        "These are AI-generated preventive suggestions. They do not replace "
        "professional agricultural advice - consult your local agricultural "
        "officer before applying any treatment."
    )


# ---------- History (Contract section 22) ----------

class ScanHistoryItem(BaseModel):
    scan_id: int
    user_id: Optional[str] = None
    crop_name: str
    timestamp: datetime
    disease_name: str
    confidence: float
    risk_level: str
    risk_score: int
    model_status: str = "PLACEHOLDER_SIMULATED"
    recommendation_summary: Optional[str] = None