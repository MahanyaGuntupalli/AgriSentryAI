"""Central configuration. No secrets hard-coded; everything comes from env vars."""
import os


class Settings:
    def __init__(self) -> None:
        self.app_name = "AgriSentry AI Backend"
        self.database_path = os.getenv("AGRISENTRY_DB", "agrisentry.db")

        # Weather (Contract section 16 / 28)
        self.weather_mode = os.getenv("WEATHER_MODE", "simulated")  # "real" | "simulated"
        self.weather_api_key = os.getenv("WEATHER_API_KEY", "")
        self.weather_cache_ttl = int(os.getenv("WEATHER_CACHE_TTL", "600"))
        self.default_lat = float(os.getenv("DEFAULT_LAT", "17.3850"))
        self.default_lon = float(os.getenv("DEFAULT_LON", "78.4867"))

        # Disease AI (Contract section 10)
        self.disease_model_path = os.getenv("DISEASE_MODEL_PATH", "")

        # Crop-identification AI (Stage 1). Empty path -> the backend looks
        # for ai/models/crop_model.h5 next to ai/models/labels.txt.
        self.crop_model_path = os.getenv("CROP_MODEL_PATH", "")
        self.crop_id_threshold = float(os.getenv("CROP_ID_THRESHOLD", "0.60"))
        self.crop_conflict_threshold = float(os.getenv("CROP_CONFLICT_THRESHOLD", "0.70"))

        self.simulated_prefix = "SIMULATED"


settings = Settings()