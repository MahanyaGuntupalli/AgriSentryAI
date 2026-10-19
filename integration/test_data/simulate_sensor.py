#!/usr/bin/env python3
"""Feeds SIMULATED sensor readings into POST /api/sensors/data.

Lets the ENTIRE software MVP run without physical hardware (Contract sections
9, 26). When the ESP32 is ready, stop this script and point the hardware at
the same endpoint - nothing else changes.

Usage:
    python simulate_sensor.py --url http://localhost:8000 --interval 10
"""
import argparse
import math
import time
from datetime import datetime, timezone

import requests

DEVICE_ID = "SIMULATED_001"   # clearly simulated (Contract section 26)


def reading(step: int) -> dict:
    """Plausible day-cycle values so charts look alive."""
    hour = datetime.now().hour + step / 60.0
    return {
        "device_id": DEVICE_ID,
        "temperature": round(26 + 5 * math.sin((hour - 9) / 24 * 2 * math.pi), 1),
        "humidity": int(60 + 22 * math.sin((hour + 3) / 24 * 2 * math.pi)),
        "soil_moisture": int(55 + 15 * math.sin(step / 40)),
        "light": max(0, int(600 + 300 * math.sin((hour - 12) / 24 * 2 * math.pi))),
        "leaf_wetness": int(50 + 30 * math.sin(step / 25)),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8000")
    ap.add_argument("--interval", type=float, default=10.0)
    args = ap.parse_args()

    step = 0
    print(f"Posting SIMULATED data from {DEVICE_ID} to {args.url} every {args.interval}s. Ctrl+C to stop.")
    while True:
        try:
            r = requests.post(f"{args.url}/api/sensors/data", json=reading(step), timeout=5)
            print(f"[{datetime.now():%H:%M:%S}] {r.status_code}  {reading(step)['temperature']}°C "
                  f"{reading(step)['humidity']}%RH")
        except requests.RequestException as e:
            print(f"Backend unreachable: {e}. Retrying...")
        step += 1
        time.sleep(args.interval)


if __name__ == "__main__":
    main()