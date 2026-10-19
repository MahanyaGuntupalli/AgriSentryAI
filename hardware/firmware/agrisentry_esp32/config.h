// AgriSentry AI - ESP32 firmware configuration (Phase 1: Hardware)
// Edit ONLY this file. The .ino reads everything from here.

// ---------- Wi-Fi ----------
const char* WIFI_SSID     = "YOUR_WIFI_NAME";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// ---------- Backend ----------
// IMPORTANT: use your computer's LAN IP (e.g. http://192.168.1.20:8000),
// NOT localhost - the ESP32 cannot reach 127.0.0.1 on your laptop.
// Find it with:  Windows: ipconfig   |   Linux/Mac: ifconfig or ip addr
const char* BACKEND_URL = "http://192.168.1.20:8000/api/sensors/data";

// ---------- Device identity ----------
// Anything not starting with "SIMULATED" is stored as source=REAL by the
// backend, so keep this prefix.
const char* DEVICE_ID = "ESP32_001";

// ---------- Timing ----------
const unsigned long SEND_INTERVAL_MS = 30000;   // one reading every 30 s

// ---------- Pins ----------
// DHT22 (temperature + humidity) - any GPIO with internal pullup
const int PIN_DHT = 4;
const int DHT_TYPE = DHT22;                     // use DHT11 if that is your module

// Analog sensors MUST be on ADC1 pins (GPIO 32-39): ADC2 stops working
// while Wi-Fi is active - a classic ESP32 trap.
const int PIN_SOIL   = 34;   // soil moisture (analog out of the sensor)
const int PIN_LDR    = 35;   // light-dependent resistor divider
const int PIN_LEAF_W = 32;   // optional leaf-wetness sensor

// ---------- Optional leaf-wetness sensor ----------
// Set false until you actually wire it; the field is simply omitted from
// the JSON when disabled (backend schema treats it as optional).
const bool ENABLE_LEAF_WETNESS = false;

// ---------- Soil sensor calibration ----------
// Run the calibration procedure in hardware/README.md and put YOUR numbers
// here. Defaults suit a typical capacitive soil sensor at 3.3 V.
const int SOIL_RAW_DRY = 3200;   // raw ADC value with sensor in dry air
const int SOIL_RAW_WET = 1300;   // raw ADC value with sensor in a glass of water

// ---------- LDR orientation ----------
// With a common 10k divider (3V3 - LDR - pin - 10k - GND) more light gives a
// HIGHER raw value. If your wiring is reversed, set this to false.
const bool LDR_HIGHER_IS_BRIGHTER = true;
