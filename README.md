# AgriSentry AI

Farmer-focused intelligent crop monitoring. SEE -> UNDERSTAND -> PREDICT -> EXPLAIN -> PREVENT.

## Quick start (software MVP, no hardware needed)

Use this `Zip2/AgriSentryAI` folder as the single project. The older `zip 1`
folder is not a second service to start; its AI module has been copied into
`ai/` here and is used automatically when a trained model is present.

```bash
# 1. Backend (Windows PowerShell)
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env                           # optional; simulated mode works out of the box
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# 2. Simulated sensor feed (new terminal)
python integration\test_data\simulate_sensor.py --url http://localhost:8000 --interval 10

# 3. API tests (new terminal)
python integration\api_tests\test_api.py

# 4. Flutter app
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator -> host PC
```

For a physical phone, replace `10.0.2.2` with the computer's LAN IP and keep
the backend bound to `0.0.0.0`.

Interactive API docs: http://localhost:8000/docs

## API summary

| Method | Endpoint | Purpose |
|---|---|---|
| GET | /api/health | backend alive check |
| POST | /api/sensors/data | receive ESP32 / simulated sensor JSON |
| GET | /api/sensors/latest | latest environmental reading |
| GET | /api/sensors/history | reading history for charts |
| GET | /api/weather/current | current weather (REAL or SIMULATED, labeled) |
| POST | /api/risk/assess | environmental risk from sensor+context |
| POST | /api/future-risk/estimate | 24h/48h/72h prototype estimate |
| POST | /api/explain | WHY? farmer-friendly explanation |
| POST | /api/recommend | WHAT TO DO? recommendations |
| POST | /api/analyze | full multimodal analysis (multipart image) |
| GET | /api/history | scan history |

## Configuration (backend/.env)

- `WEATHER_MODE=simulated` (default, labeled) or `real` + `WEATHER_API_KEY` (OpenWeatherMap)
- `DISEASE_MODEL_PATH` - optional path to a trained model. The backend also
  checks `ai/models/tomato_disease_model.h5`; until a model exists it returns
  `PLACEHOLDER_SIMULATED` with `NO_RELIABLE_DISEASE` rather than inventing a
  disease
- `DEFAULT_LAT` / `DEFAULT_LON` - farm location for weather

## Real vs simulated

Every response carrying sensor or weather data includes a `source` field:
`REAL` (ESP32 / weather API) or `SIMULATED` (development). The Flutter app
displays a SIMULATED banner so prototype data is never mistaken for live data.

## ESP32 connection (later - hardware swap, no redesign)

1. Flash the firmware from `hardware/firmware/` (hardware team's deliverable).
2. In the firmware config set the backend URL to your laptop's LAN IP,
   e.g. `http://192.168.1.20:8000` (NOT localhost - the ESP32 cannot reach it).
3. The device posts the exact same JSON contract to `/api/sensors/data`
   with `device_id=ESP32_001` -> automatically stored as `source=REAL`.
4. Stop `simulate_sensor.py`. Done - the risk engine, app and history
   keep working unchanged.

## MVP test checklist

See `integration/documentation/MVP_CHECKLIST.md` (from the Integration Contract, section 36).