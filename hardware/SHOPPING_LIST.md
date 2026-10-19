# AgriSentry AI — ESP32 Node: Shopping List + Wiring Checklist

Prices are India retail, checked September 2026 (Robu.in where linked).
Order everything from **one store** (Robu carries all of it) to save shipping.

## Shopping list

| # | Item | Qty | Price | Where |
|---|---|---|---|---|
| 1 | ESP32 DevKit V1 (ESP32-WROOM-32, 38-pin) | 1 | **₹399** | [Robu](https://robu.in/product/esp32-38pin-development-board-wifibluetooth-ultra-low-power-consumption-dual-core/) |
| 2 | DHT22 / AM2302 temp + humidity sensor | 1 | **₹105–124** | [Robu](https://robu.in/product/dht22-digital-temperature-humidity-sensor-temperature-humidity-module-am2302/) |
| 3 | Capacitive soil moisture sensor (v1.2 / v2.0) | 1 | **₹47–79** | [Robu ₹47](https://robu.in/product/capacitive-soil-moisture-sensor-v2-0/) · Probots ₹79 |
| 4 | LDR 5 mm (GL5528/5539) — buy a 10-pack, they're fragile | 1 pack | **₹18–59** | [Robu ₹59/10pc](https://robu.in/product-category/light-dependant-resistors-ldr/) |
| 5 | 10 kΩ resistors ×2 (DHT pull-up + LDR divider) — a 25-pack | 1 | **~₹20–30** | any hobby store / Robu resistor pack |
| 6 | Solderless breadboard, 840 tie points (GL-12) | 1 | **~₹75–90** | Robu |
| 7 | Jumper wires — 40 pc male→female + 40 pc male→male | 1 each | **~₹44 each** | Robu |
| 8 | Micro-USB cable (**data-capable** — charge-only cables are the #1 "board not detected" cause) | 1 | ₹0–100 | you probably own one |

**Core total: ≈ ₹760–950 + shipping** (~₹800–1,100 delivered).

Cheaper-combo alternative: the **MB102 kit** (breadboard + power module + 140
jumpers) at **₹279** on Robu replaces items 6+7 and includes a spare power
module you won't need for this build.

Optional (skip for now — `ENABLE_LEAF_WETNESS = false` in `config.h`):
leaf-wetness can be two galvanized nails ~2 cm apart in a sponge (≈₹20), or a
dedicated module (₹150–300).

## Wiring checklist

⚠️ **Two rules that prevent 90 % of first-build failures:**
1. Power **everything from 3V3**, never VIN/5V — the ADC scale assumes 3.3 V.
2. Analog sensors only on **GPIO 32–39 (ADC1)**. ADC2 pins (0, 2, 4, 12–15,
   25–27) die while Wi-Fi is on.

### Pre-flight
- [ ] Wi-Fi network is **2.4 GHz** (ESP32 cannot join 5 GHz)
- [ ] Laptop + ESP32 will be on that same network
- [ ] USB cable passes data (plug into phone — it should offer file transfer)

### Wiring — one sensor at a time, USB unplugged

| Sensor | VCC | GND | Signal | Extra |
|---|---|---|---|---|
| DHT22 | 3V3 | GND | **GPIO 4** | 10 kΩ pull-up between DATA and 3V3 |
| Soil (capacitive) | 3V3 | GND | **GPIO 34** | use **AOUT**, never DOUT |
| LDR divider | 3V3 → LDR | — | **GPIO 35** | LDR → node → 10 kΩ → GND; node → GPIO35 |

- [ ] **1. DHT only:** wire DHT22, flash, Serial Monitor 115200 → expect
      `T=..C RH=..%` (nan ⇒ pull-up or wrong pin)
- [ ] **2. Add soil:** print `soilRaw` (add `Serial.println()` or use the debug
      line) → dry air = high, glass of water = low (barely moves ⇒ wrong pin
      or potentiometer)
- [ ] **3. Calibrate soil:** note dry-air raw → `SOIL_RAW_DRY`, water raw →
      `SOIL_RAW_WET` in `config.h`, reflash → 0–100 %
- [ ] **4. Add LDR:** hand over LDR → value drops; phone torch → rises
      (inverted ⇒ `LDR_HIGHER_IS_BRIGHTER = false`)

### Connect to the backend
- [ ] `config.h`: set `WIFI_SSID`, `WIFI_PASSWORD`
- [ ] `config.h`: `BACKEND_URL = http://<LAPTOP-LAN-IP>:8000/api/sensors/data`
      (find IP with `ipconfig`; **never** localhost) — start uvicorn first
- [ ] Board "ESP32 Dev Module" → Upload → Serial Monitor 115200 → expect
      `-> backend accepted (201)`
- [ ] `curl http://localhost:8000/api/sensors/latest` → `"device_id": "ESP32_001", "source": "REAL"`
- [ ] Stop `simulate_sensor.py` so simulator + real data don't interleave
- [ ] Check the Flutter app Sensors screen shows the live values
