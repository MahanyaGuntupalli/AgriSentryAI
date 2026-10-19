import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/farm_store.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../utils/crop_intelligence.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'recommendations_screen.dart';
import 'why_screen.dart';

/// A focused view of the risk engine output and the evidence behind it.
///
/// This screen deliberately uses only values already published by the farm
/// store. It never presents a risk estimate when there is no scan to support it.
class RiskScreen extends StatelessWidget {
  const RiskScreen({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
        valueListenable: LanguageService.instance.language,
        builder: (context, _, __) => AnimatedBuilder(
          animation: Listenable.merge([
            FarmStore.instance.lastScan,
            FarmStore.instance.environment,
            FarmStore.instance.weather,
            FarmStore.instance.backendReachable,
          ]),
          builder: (context, _) {
            final store = FarmStore.instance;
            final scan = store.lastScan.value;
            final environment = store.environment.value;
            final weather = store.weather.value;
            return Scaffold(
              appBar: AppBar(
                title: Text(tr('Risk intelligence')),
                actions: const [
                  SpeakButton(text: _spokenRisk),
                  LanguageToggleButton(),
                ],
              ),
              body: scan == null
                  ? EmptyView(
                      title: tr('No risk assessment yet'),
                      message: tr(
                          'Scan a leaf to combine visual symptoms with field conditions.'),
                      actionLabel: tr('SCAN CROP'),
                      onAction: () => Navigator.pop(context),
                    )
                  : ListView(
                      padding: Spacing.page,
                      children: [
                        if (!store.backendReachable.value)
                          const OfflineBanner(),
                        if (environment?.source == 'SIMULATED')
                          const SimulatedBanner(),
                        _RiskHero(scan: scan),
                        SectionHeader(tr('Why this risk level?')),
                        _FactorList(scan: scan, environment: environment, weather: weather),
                        SectionHeader(tr('Estimated future risk')),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FutureRiskChart(scan.futureRisk.points),
                              const SizedBox(height: Spacing.sm),
                              RiskTimeline(scan.futureRisk.points),
                              const SizedBox(height: Spacing.sm),
                              Text(
                                tr(scan.futureRisk.disclaimer.isEmpty
                                    ? estimatedRiskNote()
                                    : scan.futureRisk.disclaimer),
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SectionHeader(tr('What to consider next')),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ActionRow(
                                icon: Icons.visibility_outlined,
                                title: tr('Review the detected symptoms'),
                                detail: tr(
                                    'Open the explanation to understand the evidence behind this estimate.'),
                                onTap: () => _openWhy(context, scan),
                              ),
                              const Divider(height: 24),
                              _ActionRow(
                                icon: Icons.checklist_outlined,
                                title: tr('Review recommendations'),
                                detail: tr(
                                    'Use the action list as guidance and confirm treatment decisions locally.'),
                                onTap: () => _openRecommendations(context, scan),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Spacing.xl),
                      ],
                    ),
            );
          },
        ),
      );

  static String _spokenRisk() {
    final scan = FarmStore.instance.lastScan.value;
    if (scan == null) return tr('No risk assessment is available yet.');
    return '${tr('Current risk')}: ${trLevel(scan.risk.level)}, '
        '${scan.risk.score}%. ${scan.risk.factors.map(tr).join(' ')}';
  }

  static void _openWhy(BuildContext context, ImageAnalysisResult scan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WhyScreen(result: scan),
      ),
    );
  }

  static void _openRecommendations(
      BuildContext context, ImageAnalysisResult scan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecommendationsScreen(result: scan),
      ),
    );
  }
}

class _RiskHero extends StatelessWidget {
  final ImageAnalysisResult scan;
  const _RiskHero({required this.scan});

  @override
  Widget build(BuildContext context) => AppCard(
        color: AppColors.forest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('CURRENT ENVIRONMENTAL RISK'),
              style: const TextStyle(
                color: AppColors.leafLight,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                RiskGauge(score: scan.risk.score, level: scan.risk.level),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${scan.risk.score}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        trLevel(scan.risk.level),
                        style: TextStyle(
                          color: AppColors.riskColor(scan.risk.level),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${tr('Detected')}: ${trDisease(scan.disease.name)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _FactorList extends StatelessWidget {
  final ImageAnalysisResult scan;
  final EnvironmentalData? environment;
  final WeatherData? weather;
  const _FactorList({
    required this.scan,
    required this.environment,
    required this.weather,
  });

  @override
  Widget build(BuildContext context) {
    final factors = <_RiskFactor>[
      _RiskFactor(
        icon: Icons.eco_outlined,
        title: tr('Disease'),
        value: '${trDisease(scan.disease.name)} · ${scan.disease.confidencePct}%',
        detail: tr('Visual symptoms detected in the leaf image.'),
        color: AppColors.pine,
      ),
      if (environment != null)
        _RiskFactor(
          icon: Icons.water_drop_outlined,
          title: tr('Humidity'),
          value: '${environment!.humidity.toStringAsFixed(0)}%',
          detail: tr(sensorContext('humidity', environment!.humidity)),
          color: AppColors.sky,
        ),
      if (environment != null)
        _RiskFactor(
          icon: Icons.grass,
          title: tr('Soil Moisture'),
          value: '${environment!.soilMoisture.toStringAsFixed(0)}%',
          detail: tr(sensorContext('soil', environment!.soilMoisture)),
          color: AppColors.soil,
        ),
      if (weather != null)
        _RiskFactor(
          icon: Icons.cloud_outlined,
          title: tr('Weather'),
          value: tr(weather!.condition ?? 'Unavailable'),
          detail: weather!.forecastTrend == 'WORSENING'
              ? tr('Rain or worsening weather may increase disease pressure.')
              : tr('Weather outlook is stable or improving.'),
          color: AppColors.sky,
        ),
    ];
    return Column(
      children: factors
          .map((factor) => Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: AppCard(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: factor.color.withValues(alpha: 0.12),
                        child: Icon(factor.icon, color: factor.color, size: 20),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    factor.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.forest,
                                    ),
                                  ),
                                ),
                                Text(
                                  factor.value,
                                  style: TextStyle(
                                    color: factor.color,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              factor.detail,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _RiskFactor {
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;
  const _RiskFactor({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
  });
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.pine),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(detail,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12.5, height: 1.4)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      );
}
