import '../models/models.dart';
import '../services/translations.dart';

/// Farmer-facing severity derived from disease name + risk, not a separate model.
String estimatedSeverity(ImageAnalysisResult? scan) {
  if (scan == null) return 'UNKNOWN';
  if (scan.disease.status == 'NO_RELIABLE_DISEASE' ||
      scan.disease.status == 'UNAVAILABLE') {
    return 'UNKNOWN';
  }
  final healthy = scan.disease.name.toLowerCase() == 'healthy';
  if (healthy) return 'NONE';
  if (scan.risk.level == 'CRITICAL' || scan.risk.score >= 85) return 'HIGH';
  if (scan.risk.level == 'HIGH' || scan.risk.score >= 60) return 'MEDIUM';
  if (scan.risk.level == 'MEDIUM') return 'LOW';
  return 'LOW';
}

String healthLabelForScore(int health) => health >= 70
    ? 'GOOD'
    : health >= 40
        ? 'FAIR'
        : 'AT RISK';

int cropHealthFromScan(ImageAnalysisResult? scan) =>
    scan == null ? 0 : (100 - scan.risk.score).clamp(0, 100);

String sensorBand(String kind, double value) {
  switch (kind) {
    case 'humidity':
      if (value >= 80) return 'HIGH';
      if (value >= 60) return 'MODERATE';
      return 'NORMAL';
    case 'soil':
      if (value >= 75) return 'HIGH';
      if (value <= 30) return 'LOW';
      return 'NORMAL';
    case 'temp':
      if (value >= 32) return 'HIGH';
      if (value <= 15) return 'LOW';
      return 'NORMAL';
    case 'light':
      if (value < 200) return 'LOW';
      return 'NORMAL';
    default:
      return 'NORMAL';
  }
}

String sensorContext(String kind, double value) {
  switch (kind) {
    case 'humidity':
      if (value >= 80) {
        return 'Environmental condition may increase disease risk.';
      }
      return 'Humidity is within a typical range.';
    case 'soil':
      if (value >= 75) {
        return 'High soil moisture can keep leaves wet longer.';
      }
      if (value <= 30) return 'Soil is dry; the plant may be under stress.';
      return 'Soil moisture looks typical.';
    case 'temp':
      if (value >= 22 && value <= 30) {
        return 'Temperature can favor some leaf diseases.';
      }
      return 'Temperature is not an extra warning by itself.';
    case 'light':
      if (value < 200) return 'Low light can slow drying after rain.';
      return 'Light level looks usable for the crop.';
    default:
      return '';
  }
}

bool isLiveSource(String? source) =>
    source != null && source.toUpperCase() == 'REAL';

String dataFreshnessLabel(DateTime? timestamp) {
  if (timestamp == null) return 'No reading';
  final age = DateTime.now().difference(timestamp);
  if (age.inMinutes < 2) return 'Just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) return '${age.inHours}h ago';
  return '${age.inDays}d ago';
}

List<AlertItem> alertsFromFarm({
  required EnvironmentalData? env,
  required WeatherData? weather,
  required ImageAnalysisResult? scan,
  required bool backendReachable,
}) {
  final items = <AlertItem>[];
  final now = DateTime.now();

  if (!backendReachable) {
    items.add(AlertItem(
      id: 'offline',
      title: 'Backend unavailable',
      body:
          'Showing cached or simulated information. Live sensors and AI are not confirmed.',
      severity: 'MEDIUM',
      type: 'sync',
      timestamp: now,
    ));
  }

  if (scan != null && scan.disease.name.toLowerCase() != 'healthy') {
    items.add(AlertItem(
      id: 'disease',
      title: 'Disease detected',
      body:
          '${scan.disease.name} (${scan.disease.confidencePct}% confidence). Current risk ${scan.risk.level}.',
      severity: scan.risk.level == 'LOW' ? 'MEDIUM' : scan.risk.level,
      type: 'risk',
      timestamp: now,
    ));
  }

  if (env != null && env.humidity >= 80) {
    items.add(AlertItem(
      id: 'humidity',
      title: 'High humidity',
      body:
          'Humidity is ${env.humidity.toStringAsFixed(0)}%. Watch for leaf diseases.',
      severity: 'MEDIUM',
      type: 'environment',
      timestamp: env.timestamp,
    ));
  }

  if (env != null && env.soilMoisture >= 75) {
    items.add(AlertItem(
      id: 'soil',
      title: 'High soil moisture',
      body:
          'Soil moisture is ${env.soilMoisture.toStringAsFixed(0)}%. Prolonged wetness can raise risk.',
      severity: 'MEDIUM',
      type: 'environment',
      timestamp: env.timestamp,
    ));
  }

  if (weather != null &&
      (weather.forecastTrend == 'WORSENING' ||
          (weather.condition ?? '').toLowerCase().contains('rain'))) {
    items.add(AlertItem(
      id: 'rain',
      title: 'Rain expected',
      body:
          'Rain or worsening weather may increase disease risk. Check that leaves can dry quickly.',
      severity: 'MEDIUM',
      type: 'weather',
      timestamp: weather.timestamp,
    ));
  }

  if (env != null && env.source == 'SIMULATED') {
    items.add(AlertItem(
      id: 'sim',
      title: 'Sensor feed is simulated',
      body:
          'ESP32 live readings are not confirmed. Values are development or fallback data.',
      severity: 'LOW',
      type: 'environment',
      timestamp: env.timestamp,
    ));
  }

  return items;
}

class HistoryAnalytics {
  final int totalScans;
  final int healthyScans;
  final int diseaseDetections;
  final double averageConfidence;
  final String? mostDetected;
  final double averageRisk;
  HistoryAnalytics({
    required this.totalScans,
    required this.healthyScans,
    required this.diseaseDetections,
    required this.averageConfidence,
    required this.mostDetected,
    required this.averageRisk,
  });

  factory HistoryAnalytics.from(List<ScanHistoryItem> items) {
    if (items.isEmpty) {
      return HistoryAnalytics(
        totalScans: 0,
        healthyScans: 0,
        diseaseDetections: 0,
        averageConfidence: 0,
        mostDetected: null,
        averageRisk: 0,
      );
    }
    final healthy =
        items.where((e) => e.diseaseName.toLowerCase() == 'healthy').length;
    final counts = <String, int>{};
    for (final e in items) {
      counts[e.diseaseName] = (counts[e.diseaseName] ?? 0) + 1;
    }
    String? most;
    var max = 0;
    counts.forEach((k, v) {
      if (v > max) {
        max = v;
        most = k;
      }
    });
    final conf =
        items.map((e) => e.confidence).reduce((a, b) => a + b) / items.length;
    final risk =
        items.map((e) => e.riskScore).reduce((a, b) => a + b) / items.length;
    return HistoryAnalytics(
      totalScans: items.length,
      healthyScans: healthy,
      diseaseDetections: items.length - healthy,
      averageConfidence: conf,
      mostDetected: most,
      averageRisk: risk,
    );
  }
}

String sourceCaption(String source) {
  if (source.toUpperCase() == 'REAL') return 'LIVE DATA';
  return 'CACHED / SIMULATED';
}

String estimatedRiskNote() => tr(
    'This is an estimate based on current conditions and weather trends, not a guaranteed forecast.');
