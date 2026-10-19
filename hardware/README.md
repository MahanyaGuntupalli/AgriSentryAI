# AgriSentry AI - Hardware (Phase 1)

ESP32 environmental node: **DHT22 + soil moisture + LDR (+ optional leaf wetness)**.
The phone camera scans the leaf; this node only measures the environment
around the plant and POSTs readings to the same backend endpoint the
simulator uses. No backend or app changes are needed when you swap from
`simulate_sensor.py` to this device.

```
ESP32
 ├── DHT22 ............... temperature + humidity
 ├── Soil moisture ....... capacitive sensor (analog out)
 ├── LDR ................. light intensity (voltage divider)
 └── (optional) leaf wetness
        │
        Wi-Fi POST /api/sensors/data
        ↓
     FastAPI backend  ->  stored as source=REAL
```

## Bill of materials

| Item | Qty | Notes |
|---|---|---|
| ESP32 dev board | 1 | any WROOM-32 board |
| DHT22 (or DHT11) | 1 | temp + humidity |
| Capacitive soil moisture sensor | 1 | resistive ones corrode; avoid |
| LDR + 10 kΩ resistor | 1 | voltage divider |
| 10 kΩ resistor | 1 | DHT22 pull-up |
| Breadboard + jumper wires | - | |
| Micro-USB cable | 1 | data-capable, not charge-only |

## Wiring

Power everything from **3V3** (not VIN/5V) so ADC readings are full-range.

| Sensor | Pin | ESP32 pin | Extra |
|---|---|---|---|
| DHT22 | VCC / GND / DATA | 3V3 / GND / **GPIO4** | 10 kΩ pull-up between DATA and 3V3 |
| Soil sensor | VCC / GND / AOUT | 3V3 / GND / **GPIO34** | none |
| LDR divider | node | **GPIO35** | 3V3 - LDR - node - 10 kΩ - GND |
| Leaf wetness (optional) | node | **GPIO32** | same divider pattern as LDR |

⚠️ Analog sensors must stay on **GPIO 32-39 (ADC1)**. ADC2 pins (GPIO 0, 2, 4,
12-15, 25-27) stop working while Wi-Fi is on - the classic ESP32 trap.

## Per-sensor test (do this before flashing the full firmware)

1. **DHT22**: flash the firmware with everything else disconnected and open
   Serial Monitor (115200). You should see `T=..C RH=..%`. If you get `nan`,
   check the 10 kΩ pull-up and that DATA goes to GPIO4.
2. **Soil**: open Serial Plotter / add a `Serial.println(soilRaw)` while
   debugging. Dry air should give a high raw value, a glass of water a low one.
   If the numbers barely move, the sensor may need its potentiometer adjusted
   or you wired DOUT instead of AOUT.
3. **LDR**: cover the LDR with your hand - the light value should drop toward
   0. Shine a phone torch - it should rise toward 100. If it's inverted, set
   `LDR_HIGHER_IS_BRIGHTER = false` in `config.h`.

## Soil calibration (5 minutes, do once)

1. Flash with `SOIL_RAW_DRY = 3200` / `SOIL_RAW_WET = 1300` placeholders.
2. Temporarily add `Serial.println(soilRaw);` after the soil read (or use the
   raw debug line above).
3. Hold the sensor in **dry air** -> note the raw value -> that is `SOIL_RAW_DRY`.
4. Dip it in a **glass of water** (only the probe, not the electronics!) ->
   note the raw value -> that is `SOIL_RAW_WET`.
5. Put your two numbers in `config.h` and reflash. Readings are now 0-100 %.

## Flash it

1. Arduino IDE -> install **ESP32 board support** (Boards Manager) and the
   **"DHT sensor library" by Adafruit** (accept the Unified Sensor dependency).
2. Open `firmware/agrisentry_esp32/agrisentry_esp32.ino`.
3. Edit `config.h`:
   - `WIFI_SSID` / `WIFI_PASSWORD`
   - `BACKEND_URL` = `http://<YOUR-LAPTOP-LAN-IP>:8000/api/sensors/data`
     (find the IP with `ipconfig` on Windows; **never** `localhost`)
4. Board: "ESP32 Dev Module". Upload, open Serial Monitor at 115200.

Expected output:

```
Wi-Fi connected. IP: 192.168.1.42
T=27.4C RH=84% Soil=72% Light=54/100
-> backend accepted (201)
```

## Verify end to end

```bash
curl http://localhost:8000/api/sensors/latest
# "device_id": "ESP32_001", "source": "REAL"
```

The Flutter app (Sensors screen) and risk engine pick this up automatically -
they already consume `/api/sensors/latest` and don't care whether the reading
came from the simulator or the real device. Stop `simulate_sensor.py` once the
ESP32 is running so the two don't interleave in charts.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `backend returned -1` | uvicorn not running, or laptop firewall blocks port 8000 |
| `backend returned 422` | JSON contract mismatch - compare with `integration/api_tests/test_api.py` |
| Wi-Fi never connects | board only does 2.4 GHz; check SSID/password |
| soil always ~0 or ~100 | calibration endpoints not set for your sensor |
| DHT reads `nan` | missing pull-up, wrong GPIO, or DHT11 flashed as DHT22 (set `DHT_TYPE`) |
