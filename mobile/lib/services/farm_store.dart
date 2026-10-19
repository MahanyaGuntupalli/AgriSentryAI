import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// In-memory farm state shared across tabs after a scan or refresh.
class FarmStore {
  FarmStore._();
  static final FarmStore instance = FarmStore._();

  final ValueNotifier<ImageAnalysisResult?> lastScan =
      ValueNotifier<ImageAnalysisResult?>(null);
  final ValueNotifier<EnvironmentalData?> environment =
      ValueNotifier<EnvironmentalData?>(null);
  final ValueNotifier<WeatherData?> weather = ValueNotifier<WeatherData?>(null);
  final ValueNotifier<List<ScanHistoryItem>> history =
      ValueNotifier<List<ScanHistoryItem>>(const []);
  final ValueNotifier<bool> backendReachable = ValueNotifier<bool>(false);
  final ValueNotifier<DateTime?> lastSynced = ValueNotifier<DateTime?>(null);

  void applyScan(ImageAnalysisResult result) {
    lastScan.value = result;
    if (result.environment != null) environment.value = result.environment;
    if (result.weather != null) weather.value = result.weather;
  }
}
