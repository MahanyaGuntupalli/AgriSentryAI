"""Module 6 endpoint - current weather (REAL or clearly labeled SIMULATED)."""
from typing import Optional

from fastapi import APIRouter, Query

from ..services.weather_service import weather_service
from ..utils.errors import AppError

router = APIRouter(tags=["weather"])


@router.get("/api/weather/current")
def current_weather(lat: Optional[float] = Query(default=None),
                    lon: Optional[float] = Query(default=None)) -> dict:
    return weather_service.get_current(lat, lon).model_dump(mode="json")