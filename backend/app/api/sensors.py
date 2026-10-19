"""Sensor endpoints (Contract sections 12-13). Accepts ESP32 or SIMULATED data
with the exact same JSON contract."""
from fastapi import APIRouter

from ..database.db import db
from ..schemas.schemas import EnvironmentalData, SensorData
from ..utils.errors import AppError, error_payload

router = APIRouter(tags=["sensors"])


def _validate_ranges(d: SensorData) -> None:
    problems = []
    if not (-10 <= d.temperature <= 60):
        problems.append("Temperature value is invalid.")
    if not (0 <= d.humidity <= 100):
        problems.append("Humidity must be 0-100.")
    if not (0 <= d.soil_moisture <= 100):
        problems.append("Soil moisture must be 0-100.")
    if d.light < 0:
        problems.append("Light value is invalid.")
    if problems:
        raise AppError("INVALID_SENSOR_DATA", " ".join(problems), 422)


@router.post("/api/sensors/data", status_code=201)
def receive_sensor_data(data: SensorData) -> dict:
    _validate_ranges(data)
    db.insert_sensor(data.model_dump())
    return {"received": True, "device_id": data.device_id}


@router.get("/api/sensors/latest")
def latest_sensor(device_id: str | None = None) -> dict:
    row = db.latest_sensor(device_id)
    if not row:
        raise AppError("NO_SENSOR_DATA", "No sensor reading available yet.", 404)
    return EnvironmentalData(**row).model_dump(mode="json")


@router.get("/api/sensors/history")
def sensor_history(device_id: str | None = None, limit: int = 200) -> dict:
    return {"readings": db.sensor_history(device_id, limit)}