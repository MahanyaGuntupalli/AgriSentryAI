/// Shared models - names match Integration Contract section 8 exactly:
/// CropInfo, ImageAnalysisResult, DiseaseResult, EnvironmentalData, WeatherData,
/// RiskResult, FutureRiskResult, ExplanationResult, RecommendationResult,
/// ScanHistory.
library;

import 'package:intl/intl.dart';

class CropInfo {
  final String cropName;
  final String? growthStage;
  final String? location;
  CropInfo({this.cropName = 'tomato', this.growthStage, this.location});
}

class DiseaseResult {
  final String name;
  final double confidence; // 0..1
  final String modelStatus; // TRAINED | PLACEHOLDER_SIMULATED
  final String
      status; // HEALTHY | DISEASE_SUSPECTED | NO_RELIABLE_DISEASE | UNAVAILABLE
  final List<DiseaseCandidate> candidates;
  final List<String> evidence;
  DiseaseResult(
      {required this.name,
      required this.confidence,
      this.modelStatus = 'PLACEHOLDER_SIMULATED',
      this.status = 'NO_RELIABLE_DISEASE',
      this.candidates = const [],
      this.evidence = const []});
  factory DiseaseResult.fromJson(Map<String, dynamic> j) => DiseaseResult(
      name: j['name'] ?? 'Unknown',
      confidence: (j['confidence'] ?? 0).toDouble(),
      modelStatus: j['model_status'] ?? 'PLACEHOLDER_SIMULATED',
      status: j['status'] ?? 'NO_RELIABLE_DISEASE',
      candidates: (j['candidates'] as List? ?? const [])
          .map((e) =>
              DiseaseCandidate.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      evidence: (j['evidence'] as List? ?? const []).cast<String>());
  int get confidencePct => (confidence * 100).round();
}

class DiseaseCandidate {
  final String name;
  final double confidence;
  const DiseaseCandidate({required this.name, required this.confidence});
  factory DiseaseCandidate.fromJson(Map<String, dynamic> j) => DiseaseCandidate(
      name: j['name'] ?? 'Unknown',
      confidence: (j['confidence'] ?? 0).toDouble());
}

class PlantCandidate {
  final String name;
  final double confidence;
  const PlantCandidate({required this.name, required this.confidence});
  factory PlantCandidate.fromJson(Map<String, dynamic> j) => PlantCandidate(
      name: j['name'] ?? 'Unknown Plant',
      confidence: (j['confidence'] ?? 0).toDouble());
}

class PlantIdentification {
  final String name;
  final double confidence;
  final String status;
  final List<PlantCandidate> candidates;
  final List<String> evidence;
  const PlantIdentification({
    this.name = 'Unknown Plant',
    this.confidence = 0,
    this.status = 'UNAVAILABLE',
    this.candidates = const [],
    this.evidence = const [],
  });
  factory PlantIdentification.fromJson(Map<String, dynamic> j) =>
      PlantIdentification(
        name: j['name'] ?? 'Unknown Plant',
        confidence: (j['confidence'] ?? 0).toDouble(),
        status: j['status'] ?? 'UNAVAILABLE',
        candidates: (j['candidates'] as List? ?? const [])
            .map((e) =>
                PlantCandidate.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        evidence: (j['evidence'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class ImageQualityResult {
  final bool accepted;
  final String status;
  final List<String> reasons;
  final double brightness;
  final double blurScore;
  final int width;
  final int height;
  const ImageQualityResult({
    this.accepted = true,
    this.status = 'UNKNOWN',
    this.reasons = const [],
    this.brightness = 0,
    this.blurScore = 0,
    this.width = 0,
    this.height = 0,
  });
  factory ImageQualityResult.fromJson(Map<String, dynamic> j) =>
      ImageQualityResult(
        accepted: j['accepted'] ?? false,
        status: j['status'] ?? 'UNKNOWN',
        reasons: (j['reasons'] as List? ?? const []).cast<String>(),
        brightness: (j['brightness'] ?? 0).toDouble(),
        blurScore: (j['blur_score'] ?? 0).toDouble(),
        width: j['width'] ?? 0,
        height: j['height'] ?? 0,
      );
}

class EnvironmentalData {
  final String deviceId;
  final double temperature, humidity, soilMoisture, light;
  final DateTime timestamp;
  final String source; // REAL | SIMULATED
  final double? leafWetness;
  EnvironmentalData(
      {required this.deviceId,
      required this.temperature,
      required this.humidity,
      required this.soilMoisture,
      required this.light,
      required this.timestamp,
      this.source = 'SIMULATED',
      this.leafWetness});
  factory EnvironmentalData.fromJson(Map<String, dynamic> j) =>
      EnvironmentalData(
          deviceId: j['device_id'] ?? 'UNKNOWN',
          temperature: (j['temperature'] ?? 0).toDouble(),
          humidity: (j['humidity'] ?? 0).toDouble(),
          soilMoisture: (j['soil_moisture'] ?? 0).toDouble(),
          light: (j['light'] ?? 0).toDouble(),
          timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
          source: j['source'] ?? 'SIMULATED',
          leafWetness: j['leaf_wetness']?.toDouble());
}

class WeatherData {
  final double? temperature, humidity, rainfall;
  final String? condition, forecastTrend;
  final DateTime timestamp;
  final String source;
  WeatherData(
      {this.temperature,
      this.humidity,
      this.rainfall,
      this.condition,
      this.forecastTrend,
      required this.timestamp,
      this.source = 'SIMULATED'});
  factory WeatherData.fromJson(Map<String, dynamic> j) => WeatherData(
      temperature: j['temperature']?.toDouble(),
      humidity: j['humidity']?.toDouble(),
      rainfall: j['rainfall']?.toDouble(),
      condition: j['condition'],
      forecastTrend: j['forecast_trend'],
      timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
      source: j['source'] ?? 'SIMULATED');
}

class RiskResult {
  final String level; // LOW | MEDIUM | HIGH
  final int score; // 0..100
  final List<String> factors;
  RiskResult(
      {required this.level, required this.score, this.factors = const []});
  factory RiskResult.fromJson(Map<String, dynamic> j) => RiskResult(
      level: j['level'] ?? 'LOW',
      score: j['score'] ?? 0,
      factors: (j['factors'] as List?)?.cast<String>() ?? const []);
}

class FutureRiskPoint {
  final String horizon; // CURRENT | 24H | 48H | 72H
  final String level;
  final int score;
  final String trend;
  FutureRiskPoint(
      {required this.horizon,
      required this.level,
      required this.score,
      this.trend = 'STABLE'});
  factory FutureRiskPoint.fromJson(Map<String, dynamic> j) => FutureRiskPoint(
      horizon: j['horizon'] ?? '',
      level: j['level'] ?? 'LOW',
      score: j['score'] ?? 0,
      trend: j['trend'] ?? 'STABLE');
}

class FutureRiskResult {
  final List<FutureRiskPoint> points;
  final String modelType;
  final String disclaimer;
  FutureRiskResult(
      {required this.points,
      this.modelType = 'PROTOTYPE_RULE_BASED',
      this.disclaimer = ''});
  factory FutureRiskResult.fromJson(Map<String, dynamic> j) => FutureRiskResult(
      points: (j['points'] as List? ?? const [])
          .map((e) => FutureRiskPoint.fromJson(e))
          .toList(),
      modelType: j['model_type'] ?? 'PROTOTYPE_RULE_BASED',
      disclaimer: j['disclaimer'] ?? '');
  FutureRiskPoint? get h48 => points.length > 2 ? points[2] : null;
}

class ExplanationSection {
  final String title, body;
  final String? icon;
  ExplanationSection({required this.title, required this.body, this.icon});
  factory ExplanationSection.fromJson(Map<String, dynamic> j) =>
      ExplanationSection(
          title: j['title'] ?? '', body: j['body'] ?? '', icon: j['icon']);
}

class ExplanationResult {
  final String summary;
  final List<ExplanationSection> sections;
  final double? confidence;
  ExplanationResult(
      {required this.summary, this.sections = const [], this.confidence});
  factory ExplanationResult.fromJson(Map<String, dynamic> j) =>
      ExplanationResult(
          summary: j['summary'] ?? '',
          sections: (j['sections'] as List? ?? const [])
              .map((e) => ExplanationSection.fromJson(e))
              .toList(),
          confidence: j['confidence']?.toDouble());
}

class RecommendationItem {
  final String title, detail, urgency; // LOW | MEDIUM | HIGH | CRITICAL
  bool done;
  RecommendationItem(
      {required this.title,
      required this.detail,
      this.urgency = 'MEDIUM',
      this.done = false});
  factory RecommendationItem.fromJson(Map<String, dynamic> j) =>
      RecommendationItem(
          title: j['title'] ?? '',
          detail: j['detail'] ?? '',
          urgency: j['urgency'] ?? 'MEDIUM');
}

class RecommendationCategory {
  final List<RecommendationItem> doNow,
      manage,
      prevent,
      monitor,
      water,
      environment;
  RecommendationCategory(
      {this.doNow = const [],
      this.manage = const [],
      this.prevent = const [],
      this.monitor = const [],
      this.water = const [],
      this.environment = const []});
  factory RecommendationCategory.fromJson(Map<String, dynamic> j) =>
      RecommendationCategory(
        doNow: _l(j['do_now']),
        manage: _l(j['manage']),
        prevent: _l(j['prevent']),
        monitor: _l(j['monitor']),
        water: _l(j['water']),
        environment: _l(j['environment']),
      );
  static List<RecommendationItem> _l(dynamic v) => (v as List? ?? const [])
      .map((e) => RecommendationItem.fromJson(e))
      .toList();
}

class RecommendationResult {
  final RecommendationCategory categories;
  final String disclaimer;
  RecommendationResult({required this.categories, this.disclaimer = ''});
  factory RecommendationResult.fromJson(Map<String, dynamic> j) =>
      RecommendationResult(
          categories:
              RecommendationCategory.fromJson(j['categories'] ?? const {}),
          disclaimer: j['disclaimer'] ?? '');
}

/// Full response of POST /api/analyze (Contract section 15).
class ImageAnalysisResult {
  final int scanId;
  final PlantIdentification plant;
  final DiseaseResult disease;
  final RiskResult risk;
  final FutureRiskResult futureRisk;
  final ExplanationResult explanation;
  final RecommendationResult recommendation;
  final EnvironmentalData? environment;
  final WeatherData? weather;
  final ImageQualityResult imageQuality;
  ImageAnalysisResult(
      {required this.scanId,
      required this.disease,
      required this.risk,
      required this.futureRisk,
      required this.explanation,
      required this.recommendation,
      this.environment,
      this.weather,
      this.plant = const PlantIdentification(),
      this.imageQuality = const ImageQualityResult()});
  factory ImageAnalysisResult.fromJson(Map<String, dynamic> j) =>
      ImageAnalysisResult(
          scanId: j['scan_id'] ?? 0,
          plant: PlantIdentification.fromJson(j['plant'] ?? const {}),
          disease: DiseaseResult.fromJson(j['disease'] ?? const {}),
          risk: RiskResult.fromJson(j['risk'] ?? const {}),
          futureRisk: FutureRiskResult.fromJson(j['future_risk'] ?? const {}),
          explanation: ExplanationResult.fromJson(j['explanation'] ?? const {}),
          recommendation:
              RecommendationResult.fromJson(j['recommendation'] ?? const {}),
          environment: j['environmental_data'] == null
              ? null
              : EnvironmentalData.fromJson(j['environmental_data']),
          weather:
              j['weather'] == null ? null : WeatherData.fromJson(j['weather']),
          imageQuality:
              ImageQualityResult.fromJson(j['image_quality'] ?? const {}));
}

class ScanHistoryItem {
  final int scanId;
  final String cropName;
  final DateTime timestamp;
  final String diseaseName;
  final double confidence;
  final String riskLevel;
  final int riskScore;
  ScanHistoryItem(
      {required this.scanId,
      required this.cropName,
      required this.timestamp,
      required this.diseaseName,
      required this.confidence,
      required this.riskLevel,
      required this.riskScore});
  factory ScanHistoryItem.fromJson(Map<String, dynamic> j) => ScanHistoryItem(
      scanId: j['id'] ?? j['scan_id'] ?? 0,
      // Data integrity: an unknown crop name is kept as-is (displayed
      // honestly) instead of being silently coerced to tomato.
      cropName: j['crop_name'] ?? 'Unknown',
      timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
      diseaseName: j['disease_name'] ?? 'Unknown',
      confidence: (j['confidence'] ?? 0).toDouble(),
      riskLevel: j['risk_level'] ?? 'LOW',
      riskScore: j['risk_score'] ?? 0);
  String get dateLabel => DateFormat('dd MMM yyyy, hh:mm a').format(timestamp);
}

class AlertItem {
  final String id, title, body, severity, type;
  final DateTime timestamp;
  AlertItem(
      {required this.id,
      required this.title,
      required this.body,
      required this.severity,
      required this.type,
      required this.timestamp});
}

class ApiException implements Exception {
  final String code, message;
  final int status;
  ApiException(this.code, this.message, [this.status = 0]);
  @override
  String toString() => message;
}
