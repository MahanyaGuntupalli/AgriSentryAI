# AgriSentry AI - Final MVP Test Checklist (Contract section 36)

## Foundation
- [ ] `uvicorn app.main:app` starts without errors
- [ ] `GET /api/health` returns {"status": "ok"}
- [ ] Repository structure matches the Integration Contract

## Image
- [ ] Camera/gallery selection works in the Flutter app
- [ ] Image preview works
- [ ] Blurry/dark/small images are rejected with a farmer-friendly reason (never reach the AI)
- [ ] Valid image reaches the disease pipeline

## AI
- [ ] POST /api/analyze returns disease name + confidence
- [ ] Placeholder AI is clearly labeled `PLACEHOLDER_SIMULATED` everywhere it appears

## Environment
- [ ] simulate_sensor.py feeds data successfully
- [ ] POST /api/sensors/data validates and stores readings
- [ ] GET /api/sensors/latest returns the newest reading with source label
- [ ] An ESP32_001 reading would be stored as REAL (same code path)

## Weather
- [ ] GET /api/weather/current returns normalized data with REAL/SIMULATED source
- [ ] Backend keeps working when weather is unavailable (graceful degradation)

## Risk
- [ ] Disease + environment combine into a score (0-100) and LOW/MEDIUM/HIGH level
- [ ] Major contributing factors are listed (explainable, not a black box)

## Future risk
- [ ] CURRENT / 24H / 48H / 72H estimates returned
- [ ] Response carries model_type=PROTOTYPE_RULE_BASED and a disclaimer

## Explanation / Recommendation
- [ ] WHY explanation is farmer-friendly (no technical AI jargon)
- [ ] WHAT TO DO items are practical and carry the professional-advice disclaimer

## Integration
- [ ] Flutter connects to backend (dashboard shows live/simulated sensor data)
- [ ] Full flow works: scan -> result -> why -> recommendations -> history
- [ ] Errors follow the {"error": {"code", "message"}} contract