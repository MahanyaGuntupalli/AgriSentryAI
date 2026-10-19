/// Central configuration (Contract section 28). Nothing hard-coded elsewhere.
///
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
/// NOTE for hardware: the ESP32 must use the laptop's LAN IP, never localhost.
class AppConfig {
  /// Default reaches the host PC from an Android emulator (10.0.2.2).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// "real" = talk to FastAPI; anything else = built-in SIMULATED demo data.
  static const String dataMode = String.fromEnvironment('DATA_MODE', defaultValue: 'real');

  static const String defaultCrop = 'tomato';
  static const Duration apiTimeout = Duration(seconds: 15);
}
