#!/usr/bin/env python3
"""End-to-end API tests for the assembled MVP (Contract section 36).

Covers: health, sensors (POST/latest), weather, risk, future risk, explain,
recommend, analyze (with a generated leaf-like image), history.

Usage:
    1. Start backend:  cd backend && uvicorn app.main:app --port 8000
    2. Run:            python test_api.py
"""
import io
import sys
from datetime import datetime, timezone
import requests
from PIL import Image, ImageDraw

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
failures = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  [{'PASS' if ok else 'FAIL'}] {name} {detail}")
    if not ok:
        failures.append(name)


def make_leaf_image() -> bytes:
    """A synthetic leaf-like image that passes the quality gate."""
    img = Image.new("RGB", (640, 640), (34, 90, 40))
    d = ImageDraw.Draw(img)
    d.ellipse((120, 80, 520, 560), fill=(70, 140, 70))
    d.line((320, 100, 320, 540), fill=(40, 100, 45), width=10)
    for i in range(6):
        y = 140 + i * 70
        d.line((320, y, 480, y + 40), fill=(40, 100, 45), width=6)
        d.line((320, y, 160, y + 40), fill=(40, 100, 45), width=6)
    # some spots so it looks diseased
    for xy in [(250, 300), (380, 350), (300, 430)]:
        d.ellipse((xy[0], xy[1], xy[0] + 40, xy[1] + 40), fill=(120, 80, 40))
    # natural texture (noise) so the blur check passes on synthetic images
    import numpy as np
    a = np.asarray(img).astype(np.int16)
    a = np.clip(a + np.random.default_rng(7).integers(-12, 13, a.shape), 0, 255).astype("uint8")
    img = Image.fromarray(a)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


print(f"Testing backend at {BASE}")
print("== Stage 1: health ==")
r = requests.get(f"{BASE}/api/health", timeout=10)
check("GET /api/health", r.status_code == 200 and r.json().get("status") == "ok")

print("== Stage 3: simulated sensor ==")
payload = {"device_id": "SIMULATED_001", "temperature": 27.0, "humidity": 84.0,
           "soil_moisture": 72.0, "light": 540,
           "timestamp": datetime.now(timezone.utc).isoformat()}
r = requests.post(f"{BASE}/api/sensors/data", json=payload, timeout=10)
check("POST /api/sensors/data", r.status_code == 201)
r = requests.get(f"{BASE}/api/sensors/latest", timeout=10)
d = r.json()
check("GET /api/sensors/latest", r.status_code == 200 and d.get("humidity") == 84.0)
check("latest labeled SIMULATED", d.get("source") == "SIMULATED", f"(source={d.get('source')})")

print("== Stage 6: weather + risk ==")
r = requests.get(f"{BASE}/api/weather/current", timeout=15)
check("GET /api/weather/current", r.status_code == 200 and "source" in r.json())
weather = r.json()
risk_req = {"device_id": "SIMULATED_001", "temperature": 27.0, "humidity": 84.0,
            "soil_moisture": 72.0, "light": 540,
            "disease": {"name": "Early Blight", "confidence": 0.91,
                        "model_status": "PLACEHOLDER_SIMULATED"},
            "weather": weather}
r = requests.post(f"{BASE}/api/risk/assess", json=risk_req, timeout=10)
risk = r.json()
check("POST /api/risk/assess", r.status_code == 200 and risk.get("level") in ("LOW", "MEDIUM", "HIGH"),
      f"(level={risk.get('level')}, score={risk.get('score')})")
check("risk factors present", bool(risk.get("factors")))

print("== Stage 7: future risk / explain / recommend ==")
r = requests.post(f"{BASE}/api/future-risk/estimate",
                  json={"level": risk["level"], "score": risk["score"],
                        "factors": risk["factors"], "weather": weather}, timeout=10)
fr = r.json()
check("POST /api/future-risk/estimate", r.status_code == 200 and len(fr.get("points", [])) == 4,
      f"(model_type={fr.get('model_type')})")
r = requests.post(f"{BASE}/api/explain",
                  json={"level": risk["level"], "score": risk["score"],
                        "factors": risk["factors"],
                        "disease": risk_req["disease"], "weather": weather},
                  timeout=10)
check("POST /api/explain", r.status_code == 200 and bool(r.json().get("summary")))
r = requests.post(f"{BASE}/api/recommend",
                  json={"level": risk["level"], "score": risk["score"],
                        "factors": risk["factors"],
                        "disease": risk_req["disease"]}, timeout=10)
check("POST /api/recommend", r.status_code == 200 and "disclaimer" in r.json())

print("== Stage 5: image -> disease -> full analysis ==")
files = {"file": ("leaf.jpg", make_leaf_image(), "image/jpeg")}
r = requests.post(f"{BASE}/api/analyze", files=files,
                  data={"crop_name": "tomato", "device_id": "SIMULATED_001"}, timeout=60)
res = r.json()
check("POST /api/analyze", r.status_code == 200 and all(
    k in res for k in ("disease", "risk", "future_risk", "explanation", "recommendation")),
    f"(disease={res.get('disease', {}).get('name')}, model_status={res.get('disease', {}).get('model_status')})")
check("model status labeled", res.get("disease", {}).get("model_status") in
      ("PLACEHOLDER_SIMULATED", "TRAINED"))
if res.get("disease", {}).get("model_status") == "PLACEHOLDER_SIMULATED":
    check("placeholder cannot claim disease",
          res.get("disease", {}).get("status") == "NO_RELIABLE_DISEASE" and
          res.get("disease", {}).get("confidence") == 0)
    check("placeholder disease is excluded from risk evidence",
          not any("was detected on the leaf" in f for f in
                  res.get("risk", {}).get("factors", [])))

print("== bad image rejection ==")
dark = Image.new("RGB", (100, 100), (5, 5, 5))
buf = io.BytesIO(); dark.save(buf, format="JPEG")
r = requests.post(f"{BASE}/api/analyze", files={"file": ("dark.jpg", buf.getvalue(), "image/jpeg")},
                  data={"crop_name": "tomato"}, timeout=30)
check("dark image rejected with IMAGE_QUALITY_REJECTED",
      r.status_code == 422 and r.json().get("error", {}).get("code") == "IMAGE_QUALITY_REJECTED")

print("== Stage: error contract ==")
r = requests.post(f"{BASE}/api/sensors/data",
                  json={"device_id": "X", "temperature": 999, "humidity": 50,
                        "soil_moisture": 50, "light": 100}, timeout=10)
check("invalid sensor data -> error contract",
      r.status_code == 422 and "error" in r.json() and "code" in r.json()["error"])

print("== Stage: history ==")
r = requests.get(f"{BASE}/api/history", timeout=10)
scans = r.json().get("scans", [])
check("GET /api/history has the new scan", len(scans) >= 1, f"({len(scans)} scan(s))")

print()
if failures:
    print(f"FAILED: {failures}")
    sys.exit(1)
print("ALL TESTS PASSED")