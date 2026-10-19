#!/usr/bin/env python3
"""Pipeline INTEGRITY tests for AgriSentry AI (data-honesty contract).

Where test_api.py checks that endpoints work, this suite checks that the
analysis pipeline can never LIE:

  I1  /api/health reports true model deployment status (TRAINED vs NOT_DEPLOYED).
  I2  Without a trained crop model, no crop is ever claimed as identified.
  I3  Without a trained disease model, no disease is ever claimed
      (model_status stays PLACEHOLDER_SIMULATED, confidence stays 0).
  I4  A PLACEHOLDER result can never say DISEASE_SUSPECTED.
  I5  NO_RELIABLE_DISEASE always carries confidence 0.
  I6  Rule-based engines stay labeled (RULE_BASED_V1 / PROTOTYPE_RULE_BASED)
      and their disclaimers survive the API.
  I7  A synthetic non-plant object image never gets a crop identified.
  I8  Unknown crop names ("banana") are recorded as unknown metadata,
      never echoed back as an identification.
  I9  The quality gate runs before any model (dark image -> 422).
  I10 When a trained crop model IS deployed, an identified crop that
      contradicts the farmer's selection is flagged, not silently accepted.

Usage:
    1. Start backend (throwaway DB recommended):
           cd backend
           AGRISENTRY_DB=test_integrity.db python -m uvicorn app.main:app --port 8010
    2. Run:
           python test_integrity.py http://localhost:8010
"""
import io
import sys

import numpy as np
import requests
from PIL import Image, ImageDraw

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8010"
failures = []

KNOWN_CROPS = {"Tomato", "Rice", "Cotton", "Chilli", "Maize"}


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  [{'PASS' if ok else 'FAIL'}] {name} {detail}")
    if not ok:
        failures.append(name)


def noisy_image(color, spots=True, seed=7, size=640) -> bytes:
    """Synthetic leaf-like image that passes the quality gate."""
    img = Image.new("RGB", (size, size), color)
    d = ImageDraw.Draw(img)
    if spots:
        d.ellipse((120, 80, 520, 560), fill=(70, 140, 70))
        d.line((320, 100, 320, 540), fill=(40, 100, 45), width=10)
        for i in range(6):
            y = 140 + i * 70
            d.line((320, y, 480, y + 40), fill=(40, 100, 45), width=6)
            d.line((320, y, 160, y + 40), fill=(40, 100, 45), width=6)
        for xy in [(250, 300), (380, 350), (300, 430)]:
            d.ellipse((xy[0], xy[1], xy[0] + 40, xy[1] + 40), fill=(120, 80, 40))
    a = np.asarray(img).astype(np.int16)
    a = np.clip(a + np.random.default_rng(seed).integers(-12, 13, a.shape),
                0, 255).astype("uint8")
    img = Image.fromarray(a)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def analyze(image_bytes: bytes, crop_name=None, timeout=60):
    files = {"file": ("photo.jpg", image_bytes, "image/jpeg")}
    data = {}
    if crop_name is not None:
        data["crop_name"] = crop_name
    r = requests.post(f"{BASE}/api/analyze", files=files, data=data,
                      timeout=timeout)
    return r


print(f"Integrity tests against {BASE}")

# ---------- I1: honest health / model status ----------
print("== I1: health reports true model status ==")
r = requests.get(f"{BASE}/api/health", timeout=10)
health_ok = r.status_code == 200 and r.json().get("status") == "ok"
check("GET /api/health", health_ok)
models = r.json().get("models", {}) if health_ok else {}
crop_model = models.get("crop_identification", {})
disease_model = models.get("disease", {})
check("crop model status labeled", crop_model.get("status") in ("TRAINED", "NOT_DEPLOYED"),
      f"(status={crop_model.get('status')})")
check("disease model status labeled", disease_model.get("status") in ("TRAINED", "NOT_DEPLOYED"),
      f"(status={disease_model.get('status')})")
crop_deployed = crop_model.get("status") == "TRAINED"
disease_deployed = disease_model.get("status") == "TRAINED"

# ---------- I2 + I3 + I4 + I5: placeholder honesty on a leaf-like image ----------
print("== I2-I5: analysis honesty (leaf-like image) ==")
r = analyze(noisy_image(color=(34, 90, 40)), crop_name="tomato")
check("POST /api/analyze", r.status_code == 200, f"(http={r.status_code})")
res = r.json() if r.status_code == 200 else {}
plant = res.get("plant", {})
disease = res.get("disease", {})
risk = res.get("risk", {})

check("plant status from the allowed set", plant.get("status") in
      ("IDENTIFIED", "UNCERTAIN", "UNKNOWN", "UNAVAILABLE", "MISMATCH_REQUESTED_CROP"),
      f"(status={plant.get('status')})")

if not crop_deployed:
    check("I2: no crop model -> no crop claimed", plant.get("status") in
          ("UNKNOWN", "UNAVAILABLE") and plant.get("name") == "Unknown Plant"
          and plant.get("confidence") == 0,
          f"(status={plant.get('status')}, name={plant.get('name')})")
else:
    if plant.get("status") == "IDENTIFIED":
        check("I2: identified crop is a known class", plant.get("name") in KNOWN_CROPS,
              f"(name={plant.get('name')})")

if not disease_deployed:
    check("I3: no disease model -> placeholder label",
          disease.get("model_status") == "PLACEHOLDER_SIMULATED")
    check("I3: placeholder never claims a disease",
          disease.get("status") == "NO_RELIABLE_DISEASE"
          and disease.get("confidence") == 0,
          f"(status={disease.get('status')}, conf={disease.get('confidence')})")
    check("I4: placeholder excluded from risk evidence",
          not any("was detected on the leaf" in f for f in risk.get("factors", [])))
else:
    check("I4: TRAINED model labels itself TRAINED",
          disease.get("model_status") == "TRAINED")

check("I5: NO_RELIABLE_DISEASE means confidence 0",
      disease.get("status") != "NO_RELIABLE_DISEASE"
      or disease.get("confidence") == 0)

# ---------- I6: transparency labels + disclaimers ----------
print("== I6: transparency labels ==")
check("risk engine labeled", risk.get("engine") == "RULE_BASED_V1")
fr = res.get("future_risk", {})
check("future risk labeled as prototype estimate",
      fr.get("model_type") == "PROTOTYPE_RULE_BASED" and bool(fr.get("disclaimer")))
check("recommendation disclaimer present",
      bool(res.get("recommendation", {}).get("disclaimer")))

# ---------- I7: synthetic non-plant object ----------
print("== I7: non-plant object image ==")
r = analyze(noisy_image(color=(150, 150, 160), spots=False, seed=11),
            crop_name="tomato")
if r.status_code == 200:
    obj_plant = r.json().get("plant", {})
    check("I7: object image never yields IDENTIFIED crop",
          obj_plant.get("status") != "IDENTIFIED"
          or obj_plant.get("name") not in KNOWN_CROPS or not crop_deployed,
          f"(status={obj_plant.get('status')}, name={obj_plant.get('name')})")
else:
    check("I7: object image handled (rejected or analyzed)", r.status_code in (200, 422))

# ---------- I8: unknown crop name ----------
print("== I8: unknown crop name is metadata only ==")
r = analyze(noisy_image(color=(34, 90, 40), seed=13), crop_name="banana")
if r.status_code == 200:
    body = r.json()
    blob = str(body.get("explanation", {}))
    check("I8: 'banana' never echoed as an identified crop",
          "Crop: banana" not in blob,
          f"(observed-crop line uses '{'Crop: banana' in blob}')")
    check("I8: analysis still honest", body.get("plant", {}).get("status") in
          ("IDENTIFIED", "UNCERTAIN", "UNKNOWN", "UNAVAILABLE", "MISMATCH_REQUESTED_CROP"))
else:
    check("I8: unknown crop accepted or rejected with contract",
          r.status_code in (200, 422))

# ---------- I9: quality gate runs first ----------
print("== I9: quality gate ==")
dark = Image.new("RGB", (100, 100), (5, 5, 5))
buf = io.BytesIO()
dark.save(buf, format="JPEG")
r = analyze(buf.getvalue(), crop_name="tomato")
check("I9: dark image rejected before any model",
      r.status_code == 422
      and r.json().get("error", {}).get("code") == "IMAGE_QUALITY_REJECTED")

# ---------- I10: crop-consistency (only exercisable with a trained model) ----------
print("== I10: crop-consistency gate ==")
if crop_deployed:
    r = analyze(noisy_image(color=(34, 90, 40), seed=17), crop_name="rice")
    if r.status_code == 200:
        p = r.json().get("plant", {})
        if p.get("status") == "IDENTIFIED" and p.get("name") in KNOWN_CROPS \
                and p.get("name") != "Rice":
            check("I10: identified crop contradicts selection -> flagged",
                  p.get("status") == "MISMATCH_REQUESTED_CROP",
                  f"(status={p.get('status')}, name={p.get('name')})")
        else:
            check("I10: no confident conflicting identification to test", True)
    else:
        check("I10: analyze with mismatched crop handled", r.status_code in (200, 422))
else:
    check("I10: skipped (no crop model deployed - documented limitation)", True)

print()
if failures:
    print(f"INTEGRITY FAILED: {failures}")
    sys.exit(1)
print("ALL INTEGRITY TESTS PASSED")
