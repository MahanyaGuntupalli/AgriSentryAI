/*
 * AgriSentry AI - ESP32 environmental node (Phase 1: Hardware)
 *
 * Reads DHT22 (temperature + humidity), soil moisture, LDR light and an
 * optional leaf-wetness sensor, then POSTs the exact JSON contract the
 * backend already accepts:
 *
 *   POST /api/sensors/data
 *   {
 *     "device_id":     "ESP32_001",
 *     "temperature":   27.4,
 *     "humidity":      84.0,
 *     "soil_moisture": 72.0,
 *     "light":         540,
 *     "leaf_wetness":  65,          // optional
 *     "timestamp":     "2026-09-08T10:30:00Z"
 *   }
 *
 * The backend stores any device_id that does not start with "SIMULATED"
 * as source=REAL automatically - no backend changes needed.
 *
 * Wiring (see hardware/README.md for the full guide):
 *   DHT22  data -> GPIO4 (+ 10k pullup between data and 3V3)
 *   Soil   AOUT -> GPIO34 (ADC1)
 *   LDR    node -> GPIO35 (ADC1)
 *   Leaf   node -> GPIO32 (ADC1, optional)
 *
 * Libraries needed (Arduino IDE Library Manager):
 *   "DHT sensor library" by Adafruit (+ its "Adafruit Unified Sensor" dependency)
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include "config.h"

DHT dht(PIN_DHT, DHT_TYPE);

// ---------------------------------------------------------------- setup ---

void setup() {
  Serial.begin(115200);
  delay(200);

  // ADC: 12-bit (0-4095), 3.3 V reference, atten 11 dB = full range
  analogReadResolution(12);

  dht.begin();

  Serial.println();
  Serial.println("AgriSentry AI - ESP32 environmental node");
  Serial.printf("Device ID: %s\n", DEVICE_ID);

  connectWiFi();
}

void connectWiFi() {
  Serial.printf("Connecting to Wi-Fi '%s'", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 30000) {
    delay(500);
    Serial.print(".");
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\nWi-Fi connected. IP: %s\n", WiFi.localIP().toString().c_str());
    // NTP so the ISO timestamp in each reading is real UTC.
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  } else {
    Serial.println("\nWi-Fi NOT connected - will retry before each send.");
  }
}

// ------------------------------------------------------------- reading ---

struct Reading {
  float temperature;
  float humidity;
  float soil_moisture;
  int   light;
  int   leaf_wetness;      // -1 = not enabled / not valid
  bool  valid;
};

// Median of N samples - rejects single-wire glitch reads.
int medianAnalog(int pin) {
  const int N = 7;
  int v[N];
  for (int i = 0; i < N; i++) {
    v[i] = analogRead(pin);
    delay(5);
  }
  // insertion sort (N is tiny)
  for (int i = 1; i < N; i++) {
    int key = v[i], j = i - 1;
    while (j >= 0 && v[j] > key) { v[j + 1] = v[j]; j--; }
    v[j + 1] = key;
  }
  return v[N / 2];
}

// Map raw ADC to soil moisture percentage using the calibrated endpoints.
// Higher raw = drier for capacitive sensors, hence the reversed mapping.
int soilPercent(int raw) {
  int lo = min(SOIL_RAW_WET, SOIL_RAW_DRY);
  int hi = max(SOIL_RAW_WET, SOIL_RAW_DRY);
  long pct = map(constrain(raw, lo, hi), lo, hi, 100, 0);
  return (int)constrain(pct, 0, 100);
}

int lightPercent(int raw) {
  if (!LDR_HIGHER_IS_BRIGHTER) raw = 4095 - raw;
  long pct = map(constrain(raw, 0, 4095), 0, 4095, 0, 100);
  return (int)constrain(pct, 0, 100);
}

Reading takeReading() {
  Reading r{};
  r.leaf_wetness = -1;

  float h = dht.readHumidity();
  float t = dht.readTemperature();     // Celsius
  if (isnan(h) || isnan(t)) {
    Serial.println("DHT22 read failed - check wiring / 10k pullup. Retrying next cycle.");
    r.valid = false;
    return r;
  }

  int soilRaw = medianAnalog(PIN_SOIL);
  int ldrRaw  = medianAnalog(PIN_LDR);

  r.temperature   = t;
  r.humidity      = h;
  r.soil_moisture = soilPercent(soilRaw);
  r.light         = lightPercent(ldrRaw);
  r.valid         = true;

  if (ENABLE_LEAF_WETNESS) {
    int lwRaw = medianAnalog(PIN_LEAF_W);
    // Typical resistive leaf-wetness pad: wet = lower resistance = higher
    // raw value with the usual divider. Adjust if your module differs.
    r.leaf_wetness = (int)constrain(map(lwRaw, 0, 4095, 0, 100), 0, 100);
  }

  Serial.printf("T=%.1fC RH=%.0f%% Soil=%d%% Light=%d/100\n",
                r.temperature, r.humidity, r.soil_moisture, r.light);
  return r;
}

// ----------------------------------------------------------------- send ---

String isoTimestamp() {
  // NTP-synced UTC timestamp; falls back to epoch 0 string if sync failed.
  time_t now = time(nullptr);
  struct tm t;
  gmtime_r(&now, &t);
  char buf[25];
  strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &t);
  return String(buf);
}

bool sendToBackend(const Reading& r) {
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
    if (WiFi.status() != WL_CONNECTED) return false;
  }

  HTTPClient http;
  http.begin(BACKEND_URL);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(8000);

  String body = "{";
  body += "\"device_id\":\"" + String(DEVICE_ID) + "\",";
  body += "\"temperature\":"   + String(r.temperature, 1) + ",";
  body += "\"humidity\":"      + String(r.humidity, 1) + ",";
  body += "\"soil_moisture\":" + String(r.soil_moisture) + ",";
  body += "\"light\":"         + String(r.light);
  if (r.leaf_wetness >= 0) {
    body += ",\"leaf_wetness\":" + String(r.leaf_wetness);
  }
  body += ",\"timestamp\":\"" + isoTimestamp() + "\"";
  body += "}";

  int code = http.POST(body);
  http.end();

  if (code == 201) {
    Serial.println("-> backend accepted (201)");
    return true;
  }
  Serial.printf("-> backend returned %d (expected 201). Check BACKEND_URL and that uvicorn is running.\n", code);
  return false;
}

// ---------------------------------------------------------------- loop ---

void loop() {
  Reading r = takeReading();
  if (r.valid) {
    sendToBackend(r);
  }
  delay(SEND_INTERVAL_MS);
}
