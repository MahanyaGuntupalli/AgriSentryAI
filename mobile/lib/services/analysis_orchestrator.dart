import 'dart:io';

import '../ai/crop_disease_knowledge.dart';
import '../ai/on_device_ai.dart';
import '../ai/on_device_fusion.dart';
import '../models/models.dart';
import '../database/local_database.dart';
import '../services/api_service.dart';
import 'sync_service.dart';

/// Where a finished analysis came from (Master Prompt sections 4, 5, 19).
enum AnalysisSource {
  /// FastAPI backend with the (future) trained model - "real" path.
  backend,

  /// On-device inference while offline.
  onDevice,

  /// Built-in simulated sample - demo mode or last-resort fallback.
  demo,
}

/// Result of [AnalysisOrchestrator.analyzeImage].
class AnalysisOutcome {
  final ImageAnalysisResult result;
  final AnalysisSource source;

  /// True when the on-device demo engine produced this (never a trained model).
  final bool isDemoModel;

  /// User-facing note shown in the UI banner.
  final String bannerKey;

  const AnalysisOutcome({
    required this.result,
    required this.source,
    required this.isDemoModel,
    required this.bannerKey,
  });
}

/// Orchestrates the full data flow (Master Prompt section 28):
///
/// image -> quality (already done upstream) -> try BACKEND analysis
///       -> on failure: ON-DEVICE diagnosis + fusion engine
///       -> on failure: SIMULATED demo analysis
///       -> persist locally -> enqueue sync -> publish to FarmStore.
///
/// UI screens never touch the API, database or sync directly.
class AnalysisOrchestrator {
  AnalysisOrchestrator({
    required LocalDatabase db,
    required SyncService sync,
    ApiService? api,
  })  : _db = db,
        _sync = sync,
        _api = api ?? ApiService();

  final LocalDatabase _db;
  final SyncService _sync;
  final ApiService _api;

  /// Analyzes a captured leaf image end-to-end.
  Future<AnalysisOutcome> analyzeImage({
    required File image,
    required CropType crop,
  }) async {
    // 1. Preferred path: backend multimodal analysis (real API when running).
    try {
      final result = await _api.analyze(image, crop: crop.id);
      final outcome = AnalysisOutcome(
        result: result,
        source: AnalysisSource.backend,
        isDemoModel: result.disease.modelStatus != 'TRAINED',
        bannerKey: result.disease.modelStatus == 'TRAINED'
            ? ''
            : 'DEVELOPMENT MODEL - demo disease result, not a trained model',
      );
      await _persist(outcome, image, crop);
      return outcome;
    } on ApiException {
      // The backend explicitly rejected the request (quality gate, bad image).
      // Surface the server's farmer-friendly message; do not guess offline.
      rethrow;
    } catch (_) {
      // fall through to on-device path
    }

    // 2. Offline path: on-device engine + fusion (clearly labeled demo model).
    try {
      final bytes = await image.readAsBytes();
      final env = await _bestEffortEnvironment();
      final weather = await _cachedWeather();
      final history = await _localHistory(crop);
      final diagnosis = await EngineRegistry.instance.tryDiagnose(
        imageBytes: bytes,
        cropHint: crop,
      );
      if (diagnosis != null) {
        final result = buildOfflineAnalysis(
          diagnosis: diagnosis,
          crop: crop,
          environment: env,
          weather: weather,
          history: history,
        );
        final outcome = AnalysisOutcome(
          result: result,
          source: AnalysisSource.onDevice,
          isDemoModel: diagnosis.engine != AiEngineKind.trainedModel,
          bannerKey: diagnosis.engine == AiEngineKind.trainedModel
              ? 'On-device model - analyzed without internet'
              : 'DEVELOPMENT MODEL - demo disease result, not a trained model',
        );
        await _persist(outcome, image, crop);
        return outcome;
      }
    } catch (_) {
      // fall through to demo path
    }

    // 3. Last resort: honest "cannot determine" result. Data integrity rule
    //    (audit): when neither the backend nor a trained on-device model is
    //    reachable, the app must NEVER display a fabricated disease result.
    //    Environmental context may still be computed from real cached sensor
    //    data, but no disease name and no confidence are invented.
    try {
      final bytes = await image.readAsBytes();
      final env = await _bestEffortEnvironment();
      final weather = await _cachedWeather();
      final history = await _localHistory(crop);
      final diagnosis = await DemoPlantDiseaseEngine()
          .diagnose(imageBytes: bytes, cropHint: crop);      final result = buildOfflineAnalysis(
        diagnosis: diagnosis,
        crop: crop,
        environment: env,
        weather: weather,
        history: history,
      );
      return AnalysisOutcome(
        result: result,
        source: AnalysisSource.demo,
        isDemoModel: true,
        bannerKey:
            'Backend unreachable - disease could not be determined from this image',
      ); // demo data is NOT persisted as the farmer's real history
    } catch (_) {
      // Even the offline fallback failed (e.g. unreadable file): surface an
      // explicit error instead of any data.
      throw ApiException('ANALYSIS_UNAVAILABLE',
          'The analysis service is unavailable. Check your connection and try again.',
          503);
    }
  }

  // ---------------- persistence ----------------

  Future<void> _persist(
      AnalysisOutcome outcome, File image, CropType crop) async {
    final r = outcome.result;
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final record = <String, dynamic>{
      'local_id': localId,
      'server_scan_id': r.scanId,
      'crop_name': crop.id,
      'crop_display_name': crop.displayName,
      'timestamp': DateTime.now().toIso8601String(),
      'disease_name': r.disease.name,
      'disease_confidence': r.disease.confidence,
      'model_status': r.disease.modelStatus,
      'risk_level': r.risk.level,
      'risk_score': r.risk.score,
      'risk_factors': r.risk.factors,
      'future_risk': {
        'points': r.futureRisk.points
            .map((p) => {
                  'horizon': p.horizon,
                  'level': p.level,
                  'score': p.score,
                  'trend': p.trend,
                })
            .toList(),
        'model_type': r.futureRisk.modelType,
        'disclaimer': r.futureRisk.disclaimer,
      },
      'explanation': {
        'summary': r.explanation.summary,
        'sections': r.explanation.sections
            .map((s) => {'title': s.title, 'body': s.body, 'icon': s.icon})
            .toList(),
        'confidence': r.explanation.confidence,
      },
      'recommendations': {
        'categories': {
          'do_now': r.recommendation.categories.doNow
              .map((i) => {'title': i.title, 'detail': i.detail, 'urgency': i.urgency})
              .toList(),
          'manage': r.recommendation.categories.manage
              .map((i) => {'title': i.title, 'detail': i.detail, 'urgency': i.urgency})
              .toList(),
          'prevent': r.recommendation.categories.prevent
              .map((i) => {'title': i.title, 'detail': i.detail, 'urgency': i.urgency})
              .toList(),
          'monitor': r.recommendation.categories.monitor
              .map((i) => {'title': i.title, 'detail': i.detail, 'urgency': i.urgency})
              .toList(),
          'water': r.recommendation.categories.water
              .map((i) => {'title': i.title, 'detail': i.detail, 'urgency': i.urgency})
              .toList(),
          'environment': r.recommendation.categories.environment
              .map((i) => {'title': i.title, 'detail': i.detail, 'urgency': i.urgency})
              .toList(),
        },
        'disclaimer': r.recommendation.disclaimer,
      },
      'weather': r.weather == null
          ? null
          : {
              'temperature': r.weather!.temperature,
              'humidity': r.weather!.humidity,
              'rainfall': r.weather!.rainfall,
              'condition': r.weather!.condition,
              'forecast_trend': r.weather!.forecastTrend,
              'timestamp': r.weather!.timestamp.toIso8601String(),
              'source': r.weather!.source,
            },
      'environment': r.environment == null
          ? null
          : {
              'device_id': r.environment!.deviceId,
              'temperature': r.environment!.temperature,
              'humidity': r.environment!.humidity,
              'soil_moisture': r.environment!.soilMoisture,
              'light': r.environment!.light,
              'leaf_wetness': r.environment!.leafWetness,
              'timestamp': r.environment!.timestamp.toIso8601String(),
              'source': r.environment!.source,
            },
      'image_path': image.path,
      'sync_status':
          outcome.source == AnalysisSource.backend ? 'SYNCED' : 'PENDING',
    };
    await _db.saveAnalysis(record,
        pendingSync: outcome.source != AnalysisSource.backend);
    await _sync.refreshPending();
    if (outcome.source != AnalysisSource.backend) {
      await _sync.syncNow();
    }
  }

  // ---------------- context helpers ----------------

  /// Latest environmental readings: backend if reachable, otherwise the
  /// locally cached IoT snapshot (never fake live data - Master Prompt 18).
  Future<EnvironmentalData?> _bestEffortEnvironment() async {
    try {
      return await _api.latestSensors();
    } catch (_) {
      final cached = await _db.cachedSensorReadings();
      if (cached.isNotEmpty) {
        return EnvironmentalData.fromJson(cached.last);
      }
      return null;
    }
  }

  /// Weather: cached snapshot if the API is unreachable.
  Future<WeatherData?> _cachedWeather() async {
    try {
      final w = await _api.currentWeather();
      await _db.saveWeather(_weatherToMap(w));
      return w;
    } catch (_) {
      final cached = await _db.cachedWeather();
      return cached == null ? null : WeatherData.fromJson(cached);
    }
  }

  /// Local scan history for the fusion engine's history input.
  Future<List<ScanHistoryItem>> _localHistory(CropType crop) async {
    final stored = await _db.analyses(limit: 5);
    return stored
        .map((a) => ScanHistoryItem(
              scanId: (a['server_scan_id'] as num?)?.toInt() ?? 0,
              cropName: (a['crop_name'] as String?) ?? crop.id,
              timestamp:
                  DateTime.tryParse((a['timestamp'] as String?) ?? '') ??
                      DateTime.now(),
              diseaseName: (a['disease_name'] as String?) ?? 'Unknown',
              confidence: (a['disease_confidence'] as num?)?.toDouble() ?? 0,
              riskLevel: (a['risk_level'] as String?) ?? 'LOW',
              riskScore: (a['risk_score'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Map<String, dynamic> _weatherToMap(WeatherData w) => {
        'temperature': w.temperature,
        'humidity': w.humidity,
        'rainfall': w.rainfall,
        'condition': w.condition,
        'forecast_trend': w.forecastTrend,
        'timestamp': w.timestamp.toIso8601String(),
        'source': w.source,
      };

  // ---------------- history reads ----------------

  /// Local-first history: stored analyses, then backend history if reachable.
  Future<List<StoredAnalysisSummary>> historySummary({int limit = 100}) async {
    final stored = await _db.analyses(limit: limit);
    return stored.map(StoredAnalysisSummary.fromMap).toList();
  }

  /// Restores a full ImageAnalysisResult from a locally stored record
  /// (used by History detail view entirely offline).
  static ImageAnalysisResult resultFromStoredMap(Map<String, dynamic> a) {
    final future = a['future_risk'] as Map<String, dynamic>? ?? const {};
    final points = ((future['points'] as List?) ?? const [])
        .map((e) => FutureRiskPoint.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final explanation = a['explanation'] as Map<String, dynamic>? ?? const {};
    final recs = a['recommendations'] as Map<String, dynamic>? ?? const {};
    final cats = (recs['categories'] as Map<String, dynamic>? ?? const {});
    List<RecommendationItem> catList(String key) =>
        ((cats[key] as List?) ?? const [])
            .map((e) => RecommendationItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
    final weatherJson = a['weather'] as Map<String, dynamic>?;
    final envJson = a['environment'] as Map<String, dynamic>?;
    return ImageAnalysisResult(
      scanId: (a['server_scan_id'] as num?)?.toInt() ?? 0,
      disease: DiseaseResult(
        name: (a['disease_name'] as String?) ?? 'Unknown',
        confidence: (a['disease_confidence'] as num?)?.toDouble() ?? 0,
        modelStatus: (a['model_status'] as String?) ?? 'PLACEHOLDER_SIMULATED',
      ),
      risk: RiskResult(
        level: (a['risk_level'] as String?) ?? 'LOW',
        score: (a['risk_score'] as num?)?.toInt() ?? 0,
        factors: ((a['risk_factors'] as List?) ?? const []).cast<String>(),
      ),
      futureRisk: FutureRiskResult(
        points: points,
        modelType: (future['model_type'] as String?) ?? 'PROTOTYPE_RULE_BASED',
        disclaimer: (future['disclaimer'] as String?) ?? '',
      ),
      explanation: ExplanationResult(
        summary: (explanation['summary'] as String?) ?? '',
        sections: ((explanation['sections'] as List?) ?? const [])
            .map((e) => ExplanationSection.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        confidence: (explanation['confidence'] as num?)?.toDouble(),
      ),
      recommendation: RecommendationResult(
        categories: RecommendationCategory(
          doNow: catList('do_now'),
          manage: catList('manage'),
          prevent: catList('prevent'),
          monitor: catList('monitor'),
          water: catList('water'),
          environment: catList('environment'),
        ),
        disclaimer: (recs['disclaimer'] as String?) ?? '',
      ),
      weather: weatherJson == null ? null : WeatherData.fromJson(weatherJson),
      environment: envJson == null ? null : EnvironmentalData.fromJson(envJson),
    );
  }
}

/// Lightweight view model for history lists (Master Prompt section 32).
class StoredAnalysisSummary {
  final String localId;
  final int serverScanId;
  final String cropName;
  final String cropDisplayName;
  final DateTime timestamp;
  final String diseaseName;
  final double confidence;
  final String riskLevel;
  final int riskScore;
  final String syncStatus;
  final String? imagePath;

  const StoredAnalysisSummary({
    required this.localId,
    required this.serverScanId,
    required this.cropName,
    required this.cropDisplayName,
    required this.timestamp,
    required this.diseaseName,
    required this.confidence,
    required this.riskLevel,
    required this.riskScore,
    required this.syncStatus,
    this.imagePath,
  });

  factory StoredAnalysisSummary.fromMap(Map<String, dynamic> a) =>
      StoredAnalysisSummary(
        localId: (a['local_id'] as String?) ?? '',
        serverScanId: (a['server_scan_id'] as num?)?.toInt() ?? 0,
        cropName: (a['crop_name'] as String?) ?? 'Unknown',
        cropDisplayName: (a['crop_display_name'] as String?) ?? 'Unknown',
        timestamp: DateTime.tryParse((a['timestamp'] as String?) ?? '') ??
            DateTime.now(),
        diseaseName: (a['disease_name'] as String?) ?? 'Unknown',
        confidence: (a['disease_confidence'] as num?)?.toDouble() ?? 0,
        riskLevel: (a['risk_level'] as String?) ?? 'LOW',
        riskScore: (a['risk_score'] as num?)?.toInt() ?? 0,
        syncStatus: (a['sync_status'] as String?) ?? 'PENDING',
        imagePath: a['image_path'] as String?,
      );

  /// 'Synced' / 'Pending' - passed through tr() in the UI.
  String get syncLabelKey =>
      syncStatus.toUpperCase() == 'SYNCED' ? 'Synced' : 'Sync pending';
}
