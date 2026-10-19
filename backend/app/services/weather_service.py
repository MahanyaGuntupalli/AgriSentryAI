"""Module 6 - Weather integration (Contract section 16).

Design: a pluggable WeatherProvider so the provider can be swapped later
without rewriting the app. Two providers ship:

  OpenWeatherMapProvider  -> REAL weather (requires WEATHER_API_KEY)
  SimulatedProvider       -> SIMULATED weather, ALWAYS labeled source="SIMULATED"

WeatherService adds caching + timeout handling and normalizes everything to
the shared WeatherData schema. If weather fails, it raises AppError so the
caller can fail gracefully instead of crashing.
"""
import threading
import time
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from typing import Optional, Tuple

import requests

from ..config import settings
from ..schemas.schemas import WeatherData
from ..utils.errors import AppError


class WeatherProvider(ABC):
    @abstractmethod
    def current(self, lat: float, lon: float) -> WeatherData: ...
    @abstractmethod
    def forecast_trend(self, lat: float, lon: float) -> str:
        """Return IMPROVING | STABLE | WORSENING for the next ~72 hours."""
        ...


class OpenWeatherMapProvider(WeatherProvider):
    """REAL weather from OpenWeatherMap. Requires an API key in config."""

    BASE = "https://api.openweathermap.org"
    TIMEOUT = 8  # seconds

    def __init__(self, api_key: str):
        if not api_key:
            raise AppError("WEATHER_NOT_CONFIGURED", "Weather API key is missing.", 503)
        self.api_key = api_key

    def _get(self, path: str, params: dict) -> dict:
        params = {**params, "appid": self.api_key, "units": "metric"}
        try:
            r = requests.get(f"{self.BASE}{path}", params=params, timeout=self.TIMEOUT)
        except requests.RequestException:
            raise AppError("WEATHER_UNAVAILABLE", "Weather service could not be reached.", 503)
        if r.status_code != 200:
            raise AppError("WEATHER_UNAVAILABLE", "Weather service returned an error.", 503)
        return r.json()

    def current(self, lat: float, lon: float) -> WeatherData:
        d = self._get("/data/2.5/weather", {"lat": lat, "lon": lon})
        rain = (d.get("rain") or {}).get("1h", 0.0)
        return WeatherData(
            temperature=d.get("main", {}).get("temp"),
            humidity=d.get("main", {}).get("humidity"),
            rainfall=rain,
            condition=(d.get("weather") or [{}])[0].get("main"),
            forecast_trend=self.forecast_trend(lat, lon),
            timestamp=datetime.now(timezone.utc),
            source="REAL",
        )

    def forecast_trend(self, lat: float, lon: float) -> str:
        d = self._get("/data/2.5/forecast", {"lat": lat, "lon": lon, "cnt": 24})
        entries = d.get("list") or []
        if len(entries) < 4:
            return "STABLE"
        first = entries[: len(entries) // 2]
        second = entries[len(entries) // 2:]
        rain_prob = lambda chunk: sum(e.get("pop", 0.0) for e in chunk) / len(chunk)
        if rain_prob(second) - rain_prob(first) > 0.15:
            return "WORSENING"
        if rain_prob(first) - rain_prob(second) > 0.15:
            return "IMPROVING"
        return "STABLE"


class SimulatedProvider(WeatherProvider):
    """SIMULATED weather for development, clearly labeled.

    Deterministic-ish values derived from the hour so repeated calls look like
    a plausible day cycle. NEVER present this as real weather.
    """

    CONDITIONS = ["Clear", "Clouds", "Clouds", "Rain", "Clear", "Rain"]

    def _series(self, lat: float, lon: float):
        hour = datetime.now().hour
        base = 26.0 + 4.0 * __import__("math").sin((hour - 9) / 24 * 6.283)
        temp = round(base + ((lat + lon) % 1.0), 1)
        humidity = int(58 + 25 * __import__("math").sin((hour + 3) / 24 * 6.283))
        condition = self.CONDITIONS[hour % len(self.CONDITIONS)]
        rain = 4.0 if condition == "Rain" else 0.0
        trend = "WORSENING" if condition == "Rain" else ("IMPROVING" if hour % 6 < 2 else "STABLE")
        return temp, max(20, min(98, humidity)), condition, rain, trend

    def current(self, lat: float, lon: float) -> WeatherData:
        temp, humidity, condition, rain, trend = self._series(lat, lon)
        return WeatherData(
            temperature=temp, humidity=humidity, rainfall=rain,
            condition=condition, forecast_trend=trend,
            timestamp=datetime.now(timezone.utc), source="SIMULATED",
        )

    def forecast_trend(self, lat: float, lon: float) -> str:
        return self._series(lat, lon)[4]


class WeatherService:
    """Provider + in-memory TTL cache (Contract: caching where appropriate)."""

    def __init__(self) -> None:
        if settings.weather_mode == "real":
            self.provider: WeatherProvider = OpenWeatherMapProvider(settings.weather_api_key)
        else:
            self.provider = SimulatedProvider()
        self._cache: dict = {}
        self._lock = threading.Lock()

    def _cached(self, key: str, fn):
        with self._lock:
            hit = self._cache.get(key)
            if hit and time.time() - hit[0] < settings.weather_cache_ttl:
                return hit[1]
        value = fn()
        with self._lock:
            self._cache[key] = (time.time(), value)
        return value

    def get_current(self, lat: Optional[float] = None,
                    lon: Optional[float] = None) -> WeatherData:
        lat = lat if lat is not None else settings.default_lat
        lon = lon if lon is not None else settings.default_lon
        return self._cached(f"cur:{lat:.3f},{lon:.3f}",
                            lambda: self.provider.current(lat, lon))

    def get_forecast_trend(self, lat: Optional[float] = None,
                           lon: Optional[float] = None) -> str:
        lat = lat if lat is not None else settings.default_lat
        lon = lon if lon is not None else settings.default_lon
        return self._cached(f"trend:{lat:.3f},{lon:.3f}",
                            lambda: self.provider.forecast_trend(lat, lon))


weather_service = WeatherService()