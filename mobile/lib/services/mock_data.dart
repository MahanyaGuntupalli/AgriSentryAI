import '../models/models.dart';

/// SIMULATED development data (Contract sections 24, 26, 31).
/// Everything here is labeled SIMULATED / PLACEHOLDER_SIMULATED and exists only
/// so the GUI can be developed and demonstrated before hardware + trained
/// model exist. Real backend data always takes priority when reachable.
class MockData {
  static EnvironmentalData environment({int minutesAgo = 0}) => EnvironmentalData(
      deviceId: 'SIMULATED_001',
      temperature: 27.5,
      humidity: 82,
      soilMoisture: 64,
      light: 560,
      timestamp: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      source: 'SIMULATED',
      leafWetness: 55);

  static List<EnvironmentalData> environmentSeries({int count = 24}) =>
      List.generate(count, (i) {
        final t = 26 + 4 * (i / count);
        return EnvironmentalData(
            deviceId: 'SIMULATED_001',
            temperature: double.parse(t.toStringAsFixed(1)),
            humidity: (60 + 20 * (i / count)).roundToDouble(),
            soilMoisture: (55 + 12 * ((i % 8) / 8)).roundToDouble(),
            light: (500 + 200 * ((i % 12) / 12)).roundToDouble(),
            timestamp: DateTime.now().subtract(Duration(hours: count - i)),
            source: 'SIMULATED');
      });

  static WeatherData weather() => WeatherData(
      temperature: 28,
      humidity: 82,
      rainfall: 4,
      condition: 'Rain',
      forecastTrend: 'WORSENING',
      timestamp: DateTime.now(),
      source: 'SIMULATED');

  static ImageAnalysisResult sampleAnalysis() => ImageAnalysisResult(
      scanId: 0,
      disease: DiseaseResult(
          name: 'Early Blight',
          confidence: 0.91,
          modelStatus: 'PLACEHOLDER_SIMULATED'),
      risk: RiskResult(level: 'HIGH', score: 78, factors: const [
        'Early Blight was detected on the leaf (91% confidence).',
        'Humidity is high (82%).',
        'Temperature (27 C) favors disease development.',
      ]),
      futureRisk: FutureRiskResult(
          disclaimer: 'This is an estimate based on current conditions and '
              'weather trends, not a guaranteed forecast.',
          points: [
            FutureRiskPoint(
                horizon: 'CURRENT', level: 'HIGH', score: 78, trend: 'STABLE'),
            FutureRiskPoint(
                horizon: '24H', level: 'HIGH', score: 86, trend: 'WORSENING'),
            FutureRiskPoint(
                horizon: '48H', level: 'HIGH', score: 94, trend: 'WORSENING'),
            FutureRiskPoint(
                horizon: '72H', level: 'MEDIUM', score: 66, trend: 'IMPROVING'),
          ]),
      explanation: ExplanationResult(
          summary: 'Your crop is at high risk (78/100). Early Blight was '
              'detected and humid, warm weather helps it spread.',
          confidence: 0.91,
          sections: [
            ExplanationSection(
                title: 'What we saw',
                icon: 'leaf',
                body: 'The leaf shows signs of Early Blight. The AI is 91% sure of this.'),
            ExplanationSection(
                title: 'Environment',
                icon: 'thermometer',
                body: 'Temperature is 27 C, humidity 82%. These warm, wet '
                    'conditions help disease spread.'),
            ExplanationSection(
                title: 'Weather',
                icon: 'cloud',
                body: 'Rain is expected soon, which can increase the risk.'),
          ]),
      recommendation: RecommendationResult(
          disclaimer: 'These are AI-generated preventive suggestions. They do '
              'not replace professional agricultural advice - consult your '
              'local agricultural officer before applying any treatment.',
          categories: RecommendationCategory(
            doNow: [
              RecommendationItem(
                  title: 'Inspect the affected leaves',
                  detail: 'Check lower, older leaves first - Early Blight '
                      'usually starts there.',
                  urgency: 'HIGH'),
              RecommendationItem(
                  title: 'Remove badly infected leaves',
                  detail: 'Pick off heavily spotted leaves and destroy them. '
                      'Do not compost them.',
                  urgency: 'HIGH'),
            ],
            manage: [
              RecommendationItem(
                  title: 'Apply a suitable fungicide',
                  detail: 'Use a copper-based or recommended fungicide, '
                      'following the label. Confirm with your agricultural officer.',
                  urgency: 'MEDIUM'),
            ],
            prevent: [
              RecommendationItem(
                  title: 'Improve air circulation',
                  detail: 'Space plants properly and remove weeds so leaves '
                      'dry faster.',
                  urgency: 'MEDIUM'),
            ],
            monitor: [
              RecommendationItem(
                  title: 'Monitor daily',
                  detail: 'Check the crop every day and follow the actions above.',
                  urgency: 'HIGH'),
            ],
            water: [
              RecommendationItem(
                  title: 'Water at the base, not the leaves',
                  detail: 'Use drip or base watering early in the day so '
                      'leaves stay dry.',
                  urgency: 'HIGH'),
            ],
            environment: [
              RecommendationItem(
                  title: 'Improve airflow',
                  detail: 'Space plants and remove weeds so leaves dry '
                      'quickly after rain.',
                  urgency: 'HIGH'),
            ],
          )),
      environment: environment(),
      weather: weather());

  static List<AlertItem> alerts() => [
        AlertItem(
            id: 'a1',
            title: 'High disease risk',
            body: 'Early Blight detected and conditions favor spread.',
            severity: 'HIGH',
            type: 'risk',
            timestamp: DateTime.now()),
        AlertItem(
            id: 'a2',
            title: 'High humidity',
            body: 'Humidity stayed above 80% for hours. Watch for leaf diseases.',
            severity: 'MEDIUM',
            type: 'environment',
            timestamp: DateTime.now()),
        AlertItem(
            id: 'a3',
            title: 'Rain expected',
            body: 'Rain in the next 24h may increase disease risk.',
            severity: 'MEDIUM',
            type: 'weather',
            timestamp: DateTime.now()),
      ];

  static List<ScanHistoryItem> history() => [
        ScanHistoryItem(
            scanId: 3,
            cropName: 'tomato',
            timestamp: DateTime.now(),
            diseaseName: 'Early Blight',
            confidence: 0.91,
            riskLevel: 'HIGH',
            riskScore: 78),
        ScanHistoryItem(
            scanId: 2,
            cropName: 'tomato',
            timestamp: DateTime.now().subtract(const Duration(days: 2)),
            diseaseName: 'Healthy',
            confidence: 0.88,
            riskLevel: 'LOW',
            riskScore: 22),
        ScanHistoryItem(
            scanId: 1,
            cropName: 'tomato',
            timestamp: DateTime.now().subtract(const Duration(days: 5)),
            diseaseName: 'Bacterial Spot',
            confidence: 0.79,
            riskLevel: 'MEDIUM',
            riskScore: 55),
      ];

  static const String aiInsight =
      'Your crop currently looks healthy, but humidity is increasing. '
      'Scan a leaf soon to be sure.';
}
