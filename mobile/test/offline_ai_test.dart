import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:agrisentry_ai/ai/crop_disease_knowledge.dart';
import 'package:agrisentry_ai/ai/on_device_ai.dart';
import 'package:agrisentry_ai/ai/on_device_fusion.dart';
import 'package:agrisentry_ai/database/local_database.dart';
import 'package:agrisentry_ai/models/models.dart';
import 'package:agrisentry_ai/services/analysis_orchestrator.dart';

void main() {
  // ---------------- knowledge base ----------------
  group('crop knowledge base', () {
    test('covers all five supported crops', () {
      final crops = kDiseaseKnowledge.map((d) => d.crop).toSet();
      expect(crops.containsAll(CropType.values), isTrue);
    });

    test('every disease has actionable content', () {
      for (final d in kDiseaseKnowledge) {
        expect(d.doNow, isNotEmpty, reason: '${d.name} missing doNow');
        expect(d.prevent, isNotEmpty, reason: '${d.name} missing prevent');
        expect(d.monitorItems, isNotEmpty, reason: '${d.name} missing monitor');
      }
    });

    test('lookup is case-insensitive and falls back to healthy', () {
      expect(knowledgeFor('early blight')!.crop, CropType.tomato);
      expect(knowledgeFor('LEAF MOLD')!.name, 'Leaf Mold');
      final healthy = knowledgeOrHealthy('Totally Unknown Disease', CropType.rice);
      expect(healthy.name, 'Healthy');
    });

    test('tomato leaf mold and septoria exist (Phase 7 requirement)', () {
      expect(knowledgeFor('Leaf Mold'), isNotNull);
      expect(knowledgeFor('Septoria Leaf Spot'), isNotNull);
    });

    test('severity categories follow visible area', () {
      expect(severityFromArea(0.0), 'NONE');
      expect(severityFromArea(0.05), 'LOW');
      expect(severityFromArea(0.2), 'MEDIUM');
      expect(severityFromArea(0.4), 'HIGH');
      expect(severityFromArea(0.8), 'CRITICAL');
    });
  });

  // ---------------- on-device engines ----------------
  group('on-device AI engines', () {
    test('TFLite placeholder is honest about unavailability', () {
      final engine = TFLitePlantDiseaseEngine();
      expect(engine.isReady, isFalse);
    });

    test('demo engine is deterministic and clearly labeled', () async {
      final engine = DemoPlantDiseaseEngine();
      final a = await engine.diagnose(
          imageBytes: const [1, 2, 3], cropHint: CropType.tomato);
      final b = await engine.diagnose(
          imageBytes: const [9, 9, 9], cropHint: CropType.tomato);
      expect(a.diseaseName, b.diseaseName);
      expect(a.engine, AiEngineKind.demoModel);
      expect(engine.statusLabel, contains('DEMO'));
    });

    test('demo diagnosis maps to contract model status', () async {
      final d = await DemoPlantDiseaseEngine()
          .diagnose(imageBytes: const [1], cropHint: CropType.rice);
      final result = diseaseResultFromDiagnosis(d);
      expect(result.modelStatus, 'PLACEHOLDER_SIMULATED');
    });
  });

  // ---------------- fusion engine ----------------
  group('on-device fusion engine', () {
    const fusion = OnDeviceFusion();
    final env = EnvironmentalData(
      deviceId: 'TEST_001',
      temperature: 27,
      humidity: 89,
      soilMoisture: 78,
      light: 500,
      timestamp: DateTime.now(),
      source: 'SIMULATED',
      leafWetness: 65,
    );
    final weather = WeatherData(
      temperature: 28,
      humidity: 85,
      rainfall: 4,
      condition: 'Rain',
      forecastTrend: 'WORSENING',
      timestamp: DateTime.now(),
      source: 'SIMULATED',
    );

    test('high humidity + disease + rain = HIGH risk (one fused decision)', () {
      final disease = DiseaseResult(
        name: 'Leaf Mold',
        confidence: 0.88,
        status: 'DISEASE_SUSPECTED',
      );
      final k = knowledgeOrHealthy('Leaf Mold', CropType.tomato);
      final risk = fusion.assessRisk(
        disease: disease,
        knowledge: k,
        environment: env,
        weather: weather,
      );
      expect(risk.level, 'HIGH');
      expect(risk.factors.length, greaterThanOrEqualTo(3));
    });

    test('healthy leaf in mild conditions = LOW risk', () {
      final mildEnv = EnvironmentalData(
        deviceId: 'TEST_001',
        temperature: 24,
        humidity: 55,
        soilMoisture: 50,
        light: 600,
        timestamp: DateTime.now(),
        source: 'SIMULATED',
      );
      final disease = DiseaseResult(name: 'Healthy', confidence: 0.95);
      final k = knowledgeOrHealthy('Healthy', CropType.tomato);
      final risk = fusion.assessRisk(
          disease: disease, knowledge: k, environment: mildEnv);
      expect(risk.level, 'LOW');
    });

    test('healthy leaf in hot humid conditions = elevated environmental risk', () {
      // Even without disease, humid wet conditions carry environmental risk.
      final disease = DiseaseResult(name: 'Healthy', confidence: 0.95);
      final k = knowledgeOrHealthy('Healthy', CropType.tomato);
      final risk = fusion.assessRisk(
          disease: disease, knowledge: k, environment: env);
      expect(risk.score, greaterThan(20));
      expect(risk.factors, isNotEmpty);
    });

    test('future risk rises with disease + worsening weather', () {
      // Moderate current risk leaves headroom for the upward trend.
      final moderateEnv = EnvironmentalData(
        deviceId: 'TEST_001',
        temperature: 26,
        humidity: 75,
        soilMoisture: 60,
        light: 500,
        timestamp: DateTime.now(),
        source: 'SIMULATED',
      );
      final worsening = WeatherData(
        temperature: 27,
        humidity: 80,
        rainfall: 0,
        condition: 'Clouds',
        forecastTrend: 'WORSENING',
        timestamp: DateTime.now(),
        source: 'SIMULATED',
      );
      final disease = DiseaseResult(name: 'Early Blight', confidence: 0.9);
      final k = knowledgeOrHealthy('Early Blight', CropType.tomato);
      final current = fusion.assessRisk(
          disease: disease,
          knowledge: k,
          environment: moderateEnv,
          weather: worsening);
      expect(current.score, lessThan(100));
      final future = fusion.estimateFutureRisk(
          current: current, disease: disease, weather: worsening);
      expect(future.h48!.score, greaterThan(current.score));
      expect(future.h48!.trend, 'WORSENING');
      expect(future.disclaimer, isNotEmpty);
    });

    test('explanation cites plant, environment and risk evidence', () {
      const diagnosis = OnDeviceDiagnosis(
        plantName: 'Tomato',
        diseaseName: 'Leaf Mold',
        diseaseConfidence: 0.88,
        engine: AiEngineKind.demoModel,
      );
      final disease = diseaseResultFromDiagnosis(diagnosis);
      final k = knowledgeOrHealthy('Leaf Mold', CropType.tomato);
      final risk = fusion.assessRisk(
          disease: disease, knowledge: k, environment: env, weather: weather);
      final future = fusion.estimateFutureRisk(
          current: risk, disease: disease, weather: weather);
      final exp = fusion.buildExplanation(
        disease: disease,
        knowledge: k,
        crop: CropType.tomato,
        risk: risk,
        future: future,
        environment: env,
        weather: weather,
        diagnosis: diagnosis,
      );
      final titles = exp.sections.map((s) => s.title).toSet();
      expect(titles, containsAll(['What we saw', 'Plant identification', 'Weather', 'Risk']));
    });

    test('full offline analysis is contract-shaped and consistent', () {
      const diagnosis = OnDeviceDiagnosis(
        plantName: 'Tomato',
        diseaseName: 'Septoria Leaf Spot',
        diseaseConfidence: 0.8,
        engine: AiEngineKind.demoModel,
      );
      final result = buildOfflineAnalysis(
        diagnosis: diagnosis,
        crop: CropType.tomato,
        environment: env,
        weather: weather,
      );
      expect(result.risk.score, inInclusiveRange(0, 100));
      expect(result.futureRisk.points, hasLength(4));
      expect(result.recommendation.categories.doNow, isNotEmpty);
      expect(result.recommendation.categories.monitor, isNotEmpty);
    });
  });

  // ---------------- local database ----------------
  group('local database', () {
    late LocalDatabase db;
    late String tmpDir;

    setUp(() async {
      final tmp = await Directory.systemTemp.createTemp('agrisentry_test');
      tmpDir = tmp.path;
      db = LocalDatabase(directoryResolver: () => tmpDir);
    });

    tearDown(() async {
      try {
        await Directory(tmpDir).delete(recursive: true);
      } catch (_) {}
    });

    test('save, read and restore an analysis round-trip', () async {
      const diagnosis = OnDeviceDiagnosis(
        plantName: 'Tomato',
        diseaseName: 'Early Blight',
        diseaseConfidence: 0.9,
        engine: AiEngineKind.demoModel,
      );
      final result = buildOfflineAnalysis(
          diagnosis: diagnosis, crop: CropType.tomato, scanId: 42);
      final record = jsonDecode(jsonEncode({
        'local_id': 'local_1',
        'server_scan_id': 42,
        'crop_name': 'tomato',
        'crop_display_name': 'Tomato',
        'timestamp': DateTime.now().toIso8601String(),
        'disease_name': result.disease.name,
        'disease_confidence': result.disease.confidence,
        'model_status': result.disease.modelStatus,
        'risk_level': result.risk.level,
        'risk_score': result.risk.score,
        'risk_factors': result.risk.factors,
        'sync_status': 'PENDING',
      })) as Map<String, dynamic>;

      await db.saveAnalysis(record, pendingSync: true);
      expect(await db.pendingCount(), 1);

      final restored = await db.analysisById('local_1');
      expect(restored, isNotNull);
      final model = AnalysisOrchestrator.resultFromStoredMap(restored!);
      expect(model.disease.name, 'Early Blight');
      expect(model.risk.score, result.risk.score);
    });

    test('sync queue drains and marks synced', () async {
      final record = <String, dynamic>{
        'local_id': 'local_2',
        'server_scan_id': 0,
        'crop_name': 'rice',
        'timestamp': DateTime.now().toIso8601String(),
        'disease_name': 'Rice Blast',
        'disease_confidence': 0.7,
        'risk_level': 'MEDIUM',
        'risk_score': 50,
        'sync_status': 'PENDING',
      };
      await db.saveAnalysis(record, pendingSync: true);
      expect(await db.pendingCount(), 1);
      await db.markAnalysisSynced('local_2', 7);
      await db.dequeue('local_2');
      expect(await db.pendingCount(), 0);
      final restored = await db.analysisById('local_2');
      expect(restored!['sync_status'], 'SYNCED');
      expect(restored['server_scan_id'], 7);
    });

    test('weather cache persists', () async {
      await db.saveWeather({'temperature': 29.0, 'humidity': 80.0});
      final w = await db.cachedWeather();
      expect(w!['temperature'], 29.0);
    });
  });

  // ---------------- data integrity (quality audit) ----------------

  group('data integrity - no fabricated results', () {
    test('demo engine never names a disease or invents confidence', () async {
      final d = await DemoPlantDiseaseEngine().diagnose(
        imageBytes: [1, 2, 3],
        cropHint: CropType.tomato,
      );
      expect(d.diseaseName, 'No reliable disease detected');
      expect(d.diseaseConfidence, 0);
      expect(d.engine, AiEngineKind.demoModel);
    });

    test('offline analysis of a demo diagnosis carries honest status', () {
      const diagnosis = OnDeviceDiagnosis(
        plantName: 'Tomato',
        diseaseName: 'No reliable disease detected',
        diseaseConfidence: 0,
        engine: AiEngineKind.demoModel,
      );
      final result = buildOfflineAnalysis(
          diagnosis: diagnosis, crop: CropType.tomato);
      expect(result.disease.status, 'NO_RELIABLE_DISEASE');
      expect(result.disease.modelStatus, 'PLACEHOLDER_SIMULATED');
      expect(result.disease.name, 'No reliable disease detected');
      expect(result.disease.confidence, 0);
      // Environmental context is still computed from real inputs.
      expect(result.risk.factors, isNotEmpty);
    });

    test('unknown crop ids stay unknown - no silent tomato coercion', () {
      expect(CropType.tryParse('strawberry'), isNull);
      expect(CropType.tryParse(''), isNull);
      expect(CropType.tryParse(null), isNull);
      expect(CropType.tryParse('tomato'), CropType.tomato);
      expect(CropType.tryParse('  RICE '), CropType.rice);
      final item = ScanHistoryItem.fromJson({
        'id': 1,
        'crop_name': 'mango',
        'disease_name': 'Unknown',
        'risk_level': 'LOW',
        'risk_score': 3,
        'confidence': 0,
      });
      expect(item.cropName, 'mango');
    });
  });
}
