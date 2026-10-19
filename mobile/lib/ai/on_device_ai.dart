import '../models/models.dart';
import 'crop_disease_knowledge.dart';

/// Where an inference result came from (Master Prompt sections 4, 19, 30).
///
/// - [trainedModel]  : a real, evaluated model produced this result.
/// - [demoModel]     : deterministic demo/agronomy-based estimate - NEVER
///                     presented as a trained model by the UI.
/// - [unavailable]   : no engine could run (e.g. TFLite file missing).
enum AiEngineKind { trainedModel, demoModel, unavailable }

/// Outcome of plant + disease inference on one leaf image.
class OnDeviceDiagnosis {
  /// Detected/assumed plant, e.g. 'Tomato'.
  final String plantName;

  /// 0..1 confidence for the plant identification. Null = not attempted.
  final double? plantConfidence;

  /// True when plant identification is too uncertain to show a crop name.
  final bool plantUncertain;

  final String diseaseName;

  /// 0..1 disease confidence.
  final double diseaseConfidence;

  final AiEngineKind engine;

  /// Free-form engine note for the "View technical details" section.
  final String technicalNote;

  const OnDeviceDiagnosis({
    required this.plantName,
    this.plantConfidence,
    this.plantUncertain = false,
    required this.diseaseName,
    required this.diseaseConfidence,
    required this.engine,
    this.technicalNote = '',
  });
}

/// Contract every on-device AI engine implements.
///
/// Real TensorFlow Lite inference plugs in here (Master Prompt section 29):
/// a `TFLitePlantDiseaseEngine` should implement [PlantDiseaseEngine], load
/// the exported `.tflite` + labels, and return an [OnDeviceDiagnosis] with
/// `engine: AiEngineKind.trainedModel`. No UI or service changes needed.
abstract class PlantDiseaseEngine {
  String get id;

  /// Human-readable status for Settings / technical details.
  String get statusLabel;

  bool get isReady;

  /// Runs plant + disease inference.
  ///
  /// Implementations may throw [EngineUnavailableException] when the model
  /// files are missing or the platform is unsupported - callers are expected
  /// to fall back to the next engine in the chain.
  Future<OnDeviceDiagnosis> diagnose({
    required List<int> imageBytes,
    required CropType cropHint,
  });
}

/// Thrown by engines that cannot run in this session.
class EngineUnavailableException implements Exception {
  final String reason;
  EngineUnavailableException(this.reason);
  @override
  String toString() => reason;
}

/// -----------------------------------------------------------------------------
/// Placeholder for the future TensorFlow Lite engine.
///
/// The pipeline that will fill this in already exists in /ai (Python):
/// dataset scripts -> train.py -> exported model. When the model is exported
/// to .tflite, implement [PlantDiseaseEngine] with the tflite_flutter package,
/// register it in [EngineRegistry], and on-device inference becomes active.
/// Until then it reports unavailable - the demo engine is used instead and is
/// always clearly labeled in the UI.
/// -----------------------------------------------------------------------------
class TFLitePlantDiseaseEngine implements PlantDiseaseEngine {
  @override
  String get id => 'tflite_v1';

  @override
  String get statusLabel =>
      'TensorFlow Lite model not bundled yet - awaiting trained model export';

  @override
  bool get isReady => false;

  @override
  Future<OnDeviceDiagnosis> diagnose({
    required List<int> imageBytes,
    required CropType cropHint,
  }) async {
    throw EngineUnavailableException(
        'No .tflite model is bundled with this build.');
  }
}

/// -----------------------------------------------------------------------------
/// Demo engine (clearly labeled, deterministic).
///
/// This is NOT a trained model and it CANNOT identify disease from pixels.
/// It therefore NEVER names a disease: it reports "No reliable disease
/// detected" with zero confidence so downstream UI can never present a
/// fabricated diagnosis. Real inference requires the backend or a bundled
/// TFLite model; until then offline scans honestly report "cannot determine".
/// -----------------------------------------------------------------------------
class DemoPlantDiseaseEngine implements PlantDiseaseEngine {
  @override
  String get id => 'demo_rules_v1';

  @override
  String get statusLabel =>
      'DEMO MODEL - rule-based demo estimate, not a trained model';

  @override
  bool get isReady => true;

  @override
  Future<OnDeviceDiagnosis> diagnose({
    required List<int> imageBytes,
    required CropType cropHint,
  }) async {
    // Data integrity (audit rule: NEVER fabricate analytical values):
    // without a trained model there is no legitimate disease prediction,
    // so the engine refuses to name one - no per-crop "likely disease",
    // no invented confidence percentage.
    return OnDeviceDiagnosis(
      plantName: cropHint.displayName,
      plantConfidence: null, // user selection, not an identification
      plantUncertain: false,
      diseaseName: 'No reliable disease detected',
      diseaseConfidence: 0,
      engine: AiEngineKind.demoModel,
      technicalNote:
          'demo_rules_v1: no trained image model is bundled, so disease '
          'cannot be determined from this photo. Provide the backend API or '
          'bundle a TFLite model for real inference.',
    );
  }
}

/// Ordered engine chain: first ready engine wins; failures fall through.
class EngineRegistry {
  final List<PlantDiseaseEngine> engines;
  EngineRegistry(this.engines);

  /// Default registry used by the app. Register a real TFLite engine here.
  static EngineRegistry get instance => _instance ??=
      EngineRegistry([TFLitePlantDiseaseEngine(), DemoPlantDiseaseEngine()]);
  static EngineRegistry? _instance;

  PlantDiseaseEngine? get firstReady => engines.where((e) => e.isReady).isEmpty
      ? null
      : engines.firstWhere((e) => e.isReady);

  /// Runs the first ready engine; falls back to the demo engine and marks
  /// the result clearly when nothing better is available.
  Future<OnDeviceDiagnosis?> tryDiagnose({
    required List<int> imageBytes,
    required CropType cropHint,
  }) async {
    for (final engine in engines) {
      if (!engine.isReady) continue;
      try {
        return await engine.diagnose(
            imageBytes: imageBytes, cropHint: cropHint);
      } on EngineUnavailableException {
        continue;
      }
    }
    // Last resort: the demo engine is always ready, but keep the contract
    // honest by returning null if even that fails.
    try {
      return await DemoPlantDiseaseEngine()
          .diagnose(imageBytes: imageBytes, cropHint: cropHint);
    } catch (_) {
      return null;
    }
  }
}

/// Builds the DiseaseResult (contract model) from an on-device diagnosis,
/// carrying the honest model status through to the UI banners.
DiseaseResult diseaseResultFromDiagnosis(OnDeviceDiagnosis d) => DiseaseResult(
      name: d.diseaseName,
      confidence: d.diseaseConfidence.clamp(0.0, 1.0),
      status: d.engine == AiEngineKind.trainedModel
          ? 'DISEASE_SUSPECTED'
          : 'NO_RELIABLE_DISEASE',
      modelStatus: d.engine == AiEngineKind.trainedModel
          ? 'TRAINED'
          : 'PLACEHOLDER_SIMULATED',
    );
