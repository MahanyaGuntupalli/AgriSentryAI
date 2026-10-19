import '../models/models.dart';
import 'crop_disease_knowledge.dart';
import 'on_device_ai.dart';

/// On-device AI fusion engine (Master Prompt sections 9, 10, 11, 15).
///
/// Combines image + plant + environment + weather + history into ONE
/// agricultural decision: current risk, future risk, severity, explanation,
/// recommendations and re-check guidance - entirely offline.
///
/// TRANSPARENT RULE ENGINE, mirroring backend/app/services/risk_engine.py so
/// offline results are consistent with backend results:
///   Disease 25..50 | Humidity 0..20 | Temperature 0..15 | Soil 0..8
///   Leaf wetness 0..10 | Weather outlook 0..10 | History 0..5
///   <40 LOW | 40-69 MEDIUM | >=70 HIGH
///
/// Future risk mirrors backend/app/services/future_risk_service.py:
///   disease pressure +4/step, WORSENING +8, STABLE 0, IMPROVING -6 per step.
class OnDeviceFusion {
  const OnDeviceFusion();

  // ---------------- current risk ----------------

  RiskResult assessRisk({
    required DiseaseResult disease,
    required DiseaseKnowledge knowledge,
    EnvironmentalData? environment,
    WeatherData? weather,
    List<ScanHistoryItem> history = const [],
  }) {
    var score = 0;
    final factors = <String>[];

    // --- disease ---
    if (disease.status == 'DISEASE_SUSPECTED') {
      score += 25 + (25 * disease.confidence).round();
      factors.add(
          '${disease.name} was detected on the leaf (${disease.confidencePct}% confidence).');
    }

    // --- environment ---
    final env = environment;
    if (env != null) {
      final h = env.humidity;
      final hHigh = knowledge.favorable.humidityHigh;
      if (h >= 85) {
        score += 20;
        factors.add('Humidity is very high (${h.toStringAsFixed(0)}%).');
      } else if (h >= hHigh.round() && h >= 70) {
        score += 12;
        factors.add('Humidity is high (${h.toStringAsFixed(0)}%).');
      }

      final t = env.temperature;
      final fav = knowledge.favorable;
      if (t >= fav.tempMin && t <= fav.tempMax) {
        score += 15;
        factors.add(
            'Temperature (${t.toStringAsFixed(0)} C) favors disease development.');
      } else {
        score += 5;
      }

      final sm = env.soilMoisture;
      if (sm > 80) {
        score += 8;
        factors.add('Soil is very wet.');
      } else if (sm < 30) {
        score += 4;
        factors.add('Soil is dry; the plant is under stress.');
      }

      final lw = env.leafWetness;
      if (lw != null && lw >= 60) {
        score += 10;
        factors.add('Leaves stayed wet for a long time.');
      }
    }

    // --- weather ---
    if (weather != null) {
      if ((weather.rainfall ?? 0) > 0) {
        score += 10;
        factors.add('Rain was recorded recently.');
      } else if (weather.forecastTrend == 'WORSENING') {
        score += 10;
        factors
            .add('The weather outlook is getting worse (more rain expected).');
      }
    }

    // --- history ---
    final recentHigh =
        history.take(5).any((h) => h.riskLevel.toUpperCase() == 'HIGH');
    if (recentHigh) {
      score += 5;
      factors.add('A recent scan already showed high risk.');
    }

    score = score.clamp(0, 100);
    final level = _levelOf(score);
    if (factors.isEmpty) factors.add('Conditions look normal right now.');
    return RiskResult(level: level, score: score, factors: factors);
  }

  // ---------------- future risk ----------------

  FutureRiskResult estimateFutureRisk({
    required RiskResult current,
    required DiseaseResult disease,
    WeatherData? weather,
  }) {
    var step = switch (weather?.forecastTrend) {
      'WORSENING' => 8,
      'IMPROVING' => -6,
      _ => 0,
    };
    if (disease.status == 'DISEASE_SUSPECTED') step += 4;

    const horizons = ['CURRENT', '24H', '48H', '72H'];
    final points = <FutureRiskPoint>[];
    for (var i = 0; i < horizons.length; i++) {
      final s = (current.score + step * i).clamp(0, 100);
      points.add(FutureRiskPoint(
        horizon: horizons[i],
        level: _levelOf(s),
        score: s,
        trend: i == 0 ? 'STABLE' : _trendOf(step),
      ));
    }
    return FutureRiskResult(
      points: points,
      modelType: 'PROTOTYPE_RULE_BASED',
      disclaimer:
          'This is an estimate based on current conditions and weather trends, not a guaranteed forecast.',
    );
  }

  // ---------------- explanation ----------------

  ExplanationResult buildExplanation({
    required DiseaseResult disease,
    required DiseaseKnowledge knowledge,
    required CropType crop,
    required RiskResult risk,
    required FutureRiskResult future,
    EnvironmentalData? environment,
    WeatherData? weather,
    OnDeviceDiagnosis? diagnosis,
    String? historyNote,
  }) {
    final sections = <ExplanationSection>[];

    // What we saw (image evidence)
    final isHealthy = disease.name.trim().toLowerCase() == 'healthy';
    sections.add(ExplanationSection(
      title: 'What we saw',
      icon: 'leaf',
      body: isHealthy
          ? 'The leaf looks healthy. The AI is ${disease.confidencePct}% sure of this.'
          : 'The leaf shows signs of ${disease.name}. The AI is ${disease.confidencePct}% sure of this.',
    ));

    // Plant identification (Master Prompt section 2)
    if (diagnosis != null) {
      sections.add(ExplanationSection(
        title: 'Plant identification',
        icon: 'person',
        body: diagnosis.plantUncertain
            ? 'Plant identification is uncertain. Please capture a clearer image of the leaf and include the complete leaf in the frame.'
            : 'Detected plant: ${diagnosis.plantName}'
                '${diagnosis.plantConfidence == null ? ' (selected by you)' : ' (${(diagnosis.plantConfidence! * 100).round()}% confidence)'}.',
      ));
    }

    // Environment evidence
    final env = environment;
    if (env != null) {
      sections.add(ExplanationSection(
        title: 'Environment',
        icon: 'thermometer',
        body:
            'Temperature is ${env.temperature.toStringAsFixed(0)} C, humidity ${env.humidity.toStringAsFixed(0)}% and soil moisture ${env.soilMoisture.toStringAsFixed(0)}%. ${_envSentence(env, knowledge)}',
      ));
    }

    // Weather evidence
    final w = weather;
    if (w != null) {
      final body = switch (w.forecastTrend) {
        'WORSENING' => 'Rain is expected soon, which can increase the risk.',
        'IMPROVING' => 'The weather is expected to improve.',
        _ => 'The weather is expected to stay stable.',
      };
      sections
          .add(ExplanationSection(title: 'Weather', icon: 'cloud', body: body));
    }

    // History evidence
    if (historyNote != null && historyNote.isNotEmpty) {
      sections.add(ExplanationSection(
          title: 'History', icon: 'clock', body: historyNote));
    }

    // Risk outlook summary sentence
    sections.add(ExplanationSection(
      title: 'Risk',
      icon: 'assessment',
      body: _riskSentence(risk, future, knowledge, isHealthy),
    ));

    final summary =
        'Your crop is at ${risk.level.toLowerCase()} risk (${risk.score}/100). '
        // Complete sentences only: _trDynamic translates sentence-by-sentence,
        // so every clause here must be a standalone, dictionary-translatable
        // sentence (audit Phase 6 - no mixed-language fragments).
        '${isHealthy ? 'No disease was detected.' : '${disease.name} was detected.'} '
        '${_summaryConditionClause(environment, weather)}';

    return ExplanationResult(
      summary: summary,
      sections: sections,
      confidence: disease.confidence,
    );
  }

  // ---------------- recommendations ----------------

  RecommendationResult buildRecommendations({
    required DiseaseResult disease,
    required DiseaseKnowledge knowledge,
    required RiskResult risk,
    EnvironmentalData? environment,
    WeatherData? weather,
  }) {
    final doNow = <RecommendationItem>[];
    final prevent = <RecommendationItem>[];
    final monitor = <RecommendationItem>[];
    final water = <RecommendationItem>[];
    final manage = <RecommendationItem>[];
    final environmentItems = <RecommendationItem>[];

    final isHealthy = disease.name.trim().toLowerCase() == 'healthy';

    for (final (t, d) in knowledge.doNow) {
      final item = RecommendationItem(
          title: t,
          detail: d,
          urgency: risk.level == 'HIGH' ? 'HIGH' : 'MEDIUM');
      if (isHealthy) {
        prevent.add(item);
      } else {
        doNow.add(item);
      }
    }
    for (final (t, d) in knowledge.prevent) {
      prevent.add(RecommendationItem(title: t, detail: d, urgency: 'MEDIUM'));
    }

    // Condition-driven actions (same spirit as backend rules).
    if ((environment?.soilMoisture ?? 0) > 80) {
      water.add(RecommendationItem(
        title: 'Reduce watering for now',
        detail:
            'Soil is very wet. Extra watering keeps leaves and roots damp and helps disease.',
        urgency: 'HIGH',
      ));
    } else if ((environment?.soilMoisture ?? 100) < 30) {
      water.add(RecommendationItem(
        title: 'Water the crop',
        detail:
            'Soil moisture is low and the plant is under stress. Water at the base.',
        urgency: 'MEDIUM',
      ));
    } else {
      water.add(RecommendationItem(
        title: 'Water at the base, not the leaves',
        detail:
            'Use drip or base watering early in the day so leaves stay dry.',
        urgency: 'LOW',
      ));
    }

    if ((environment?.humidity ?? 0) >= knowledge.favorable.humidityHigh ||
        weather?.forecastTrend == 'WORSENING') {
      environmentItems.add(RecommendationItem(
        title: 'Improve airflow',
        detail:
            'Space plants and remove weeds so leaves dry faster in humid weather.',
        urgency: 'MEDIUM',
      ));
    }

    for (final m in knowledge.monitorItems) {
      monitor.add(RecommendationItem(
        title: 'Monitor: $m',
        detail: recheckLabel(knowledge),
        urgency: risk.level == 'HIGH' ? 'HIGH' : 'MEDIUM',
      ));
    }

    if (!isHealthy && risk.level == 'HIGH' && knowledge.name == 'Late Blight') {
      manage.add(RecommendationItem(
        title: 'Apply recommended fungicide urgently',
        detail:
            'Late Blight can destroy a crop within days in cool, wet weather. Consult your agricultural officer for the right product.',
        urgency: 'CRITICAL',
      ));
    }

    return RecommendationResult(
      categories: RecommendationCategory(
        doNow: doNow,
        manage: manage,
        prevent: prevent,
        monitor: monitor,
        water: water,
        environment: environmentItems,
      ),
      disclaimer:
          'These are AI-generated preventive suggestions. They do not replace professional agricultural advice - consult your local agricultural officer before applying any treatment.',
    );
  }

  // ---------------- full result ----------------

  /// Builds one complete decision (contract-shaped) fully offline.
  ImageAnalysisResult buildAnalysisResult({
    required OnDeviceDiagnosis diagnosis,
    required CropType crop,
    required DiseaseKnowledge knowledge,
    EnvironmentalData? environment,
    WeatherData? weather,
    List<ScanHistoryItem> history = const [],
    int scanId = 0,
  }) {
    final disease = diseaseResultFromDiagnosis(diagnosis);
    final risk = assessRisk(
      disease: disease,
      knowledge: knowledge,
      environment: environment,
      weather: weather,
      history: history,
    );
    final future =
        estimateFutureRisk(current: risk, disease: disease, weather: weather);
    final explanation = buildExplanation(
      disease: disease,
      knowledge: knowledge,
      crop: crop,
      risk: risk,
      future: future,
      environment: environment,
      weather: weather,
      diagnosis: diagnosis,
    );
    final recommendations = buildRecommendations(
      disease: disease,
      knowledge: knowledge,
      risk: risk,
      environment: environment,
      weather: weather,
    );
    return ImageAnalysisResult(
      scanId: scanId,
      disease: disease,
      risk: risk,
      futureRisk: future,
      explanation: explanation,
      recommendation: recommendations,
      environment: environment,
      weather: weather,
    );
  }

  // ---------------- helpers ----------------

  String _levelOf(int score) =>
      score < 40 ? 'LOW' : (score < 70 ? 'MEDIUM' : 'HIGH');

  String _trendOf(int step) =>
      step > 4 ? 'WORSENING' : (step < -4 ? 'IMPROVING' : 'STABLE');

  String _envSentence(EnvironmentalData env, DiseaseKnowledge k) {
    final fav = k.favorable;
    if (env.humidity >= fav.humidityHigh &&
        env.temperature >= fav.tempMin &&
        env.temperature <= fav.tempMax) {
      return 'These wet, warm conditions help disease spread.';
    }
    if (env.humidity >= 70) {
      return 'Humidity is within a favorable range for some diseases.';
    }
    return 'These conditions are within a normal range.';
  }

  String _riskSentence(RiskResult risk, FutureRiskResult future,
      DiseaseKnowledge k, bool healthy) {
    if (healthy) {
      return 'Conditions are currently favorable - keep monitoring regularly.';
    }
    final rising = (future.h48?.score ?? 0) > risk.score + 4;
    if (rising) {
      return 'Risk is expected to increase because conditions favor ${k.name.toLowerCase()} progression in the next 48 hours.';
    }
    return 'Conditions favor disease development, but no strong increase is expected in the next 48 hours.';
  }

  /// Closing summary sentence. Always returns a COMPLETE standalone sentence
  /// (subject + verb) so sentence-by-sentence translation stays coherent.
  String _summaryConditionClause(EnvironmentalData? env, WeatherData? weather) {
    if (env != null && env.humidity >= 80) {
      return 'Humid conditions help it spread.';
    }
    if (weather?.forecastTrend == 'WORSENING') {
      return 'The weather outlook may help it spread.';
    }
    return 'Conditions should be monitored.';
  }
}

/// Convenience top-level function used by the offline analysis pipeline.
ImageAnalysisResult buildOfflineAnalysis({
  required OnDeviceDiagnosis diagnosis,
  required CropType crop,
  EnvironmentalData? environment,
  WeatherData? weather,
  List<ScanHistoryItem> history = const [],
  int scanId = 0,
}) {
  final knowledge = knowledgeOrHealthy(diagnosis.diseaseName, crop);
  return const OnDeviceFusion().buildAnalysisResult(
    diagnosis: diagnosis,
    crop: crop,
    knowledge: knowledge,
    environment: environment,
    weather: weather,
    history: history,
    scanId: scanId,
  );
}
