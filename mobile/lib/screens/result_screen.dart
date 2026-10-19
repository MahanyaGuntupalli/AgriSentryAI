import 'dart:io';
import 'package:flutter/material.dart';
import '../ai/crop_disease_knowledge.dart';
import '../models/models.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../utils/app_routes.dart';
import '../utils/crop_intelligence.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'why_screen.dart';
import 'recommendations_screen.dart';

/// The deep AI advisor result (Master Prompt sections 11, 15, 24, 25).
///
/// Structure: Plant -> Disease -> Severity -> Current/Future Risk -> Why
/// -> Actions -> Precautions -> Monitor -> Re-check -> Technical details.
class ResultScreen extends StatelessWidget {
  final ImageAnalysisResult result;
  final File? image;
  final bool simulatedFallback;
  final CropType crop;
  const ResultScreen(
      {super.key,
      required this.result,
      this.image,
      this.simulatedFallback = false,
      this.crop = CropType.tomato});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.instance.language,
      builder: (context, lang, _) {
        final d = result.disease;
        final knowledge = knowledgeOrHealthy(d.name, crop);
        final severity = estimatedSeverity(result);
        final future = result.futureRisk.h48;
        final rising = future != null && future.score > result.risk.score + 4;
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('Leaf Analysis')),
            actions: [
              SpeakButton(text: () => spokenResult(result)),
              const LanguageToggleButton(),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(padding: Spacing.page, children: [
            if (simulatedFallback)
              const SimulatedBanner(
                  'Backend unreachable - SIMULATED result shown'),
            if (d.modelStatus == 'PLACEHOLDER_SIMULATED')
              const SimulatedBanner(
                  'DEVELOPMENT MODEL - demo disease result, not a trained model'),
            const SizedBox(height: Spacing.sm),
            AppCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Spacing.radius),
                child: SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: image != null
                      ? Image.file(image!, cacheWidth: 1200, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.sage.withValues(alpha: 0.3),
                          child: const Icon(Icons.eco,
                              size: 90, color: AppColors.pine)),
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),

            // ---------- Plant identification ----------
            _PlantIdCard(plant: result.plant),

            // ---------- Disease + severity ----------
            Center(
                child: Text(
                    d.status == 'DISEASE_SUSPECTED'
                        ? trDisease(d.name)
                        : d.status == 'HEALTHY'
                            ? tr('Healthy')
                            : tr('No reliable disease detected'),
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.forest))),
            const SizedBox(height: 4),
            if (d.status == 'DISEASE_SUSPECTED' || d.status == 'HEALTHY')
              Center(
                  child: Text(confidenceLabel(d.confidencePct),
                      style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700))),
            const SizedBox(height: 10),
            Center(
              child: _SeverityChip(severity: severity),
            ),
            const SizedBox(height: Spacing.lg),

            // ---------- Current + future risk ----------
            Row(children: [
              Expanded(
                  child: Column(children: [
                Text(tr('Current Risk'),
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                RiskBadge(result.risk.level),
              ])),
              Expanded(
                  child: Column(children: [
                Text(tr('Future Risk (48h)'),
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  RiskBadge(future?.level ?? 'LOW'),
                  if (rising) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.trending_up,
                        size: 16, color: AppColors.riskColor(future.level)),
                  ],
                ]),
              ])),
            ]),
            const SizedBox(height: Spacing.lg),

            // ---------- Why (inline summary) ----------
            AppCard(
              color: AppColors.forest,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome,
                          color: AppColors.leafLight, size: 18),
                      const SizedBox(width: 8),
                      Text(tr('Why?'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.6)),
                    ]),
                    const SizedBox(height: 8),
                    Text(tr(result.explanation.summary),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14.5, height: 1.5)),
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.leafLight),
                      onPressed: () => Navigator.push(
                          context, fadeSlideTo(WhyScreen(result: result))),
                      child: Text(tr('VIEW FULL EXPLANATION')),
                    ),
                  ]),
            ),

            // ---------- Risk outlook ----------
            const SizedBox(height: Spacing.md),
            AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(tr('RISK OUTLOOK'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.forest,
                          letterSpacing: 0.6,
                          fontSize: 13)),
                  const SizedBox(height: 14),
                  RiskTimeline(result.futureRisk.points),
                  const SizedBox(height: 10),
                  Text(tr(result.futureRisk.disclaimer),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                ])),

            // ---------- What the farmer sees (symptoms) ----------
            const SizedBox(height: Spacing.md),
            if (d.status == 'DISEASE_SUSPECTED' || d.status == 'HEALTHY')
              AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.search,
                            size: 18, color: AppColors.pine),
                        const SizedBox(width: 8),
                        Text(tr('What to look for'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.forest,
                                fontSize: 15)),
                      ]),
                      const SizedBox(height: 8),
                      Text(tr(knowledge.symptoms),
                          style: const TextStyle(
                              color: AppColors.muted,
                              height: 1.5,
                              fontSize: 13.5)),
                    ]),
              )
            else
              AppCard(
                color: AppColors.amber.withValues(alpha: 0.10),
                child: Text(
                  tr('The available image evidence is not strong enough to name a disease. Environmental conditions may affect future risk, but they do not prove a current disease.'),
                  style: const TextStyle(height: 1.5, color: AppColors.ink),
                ),
              ),

            // ---------- Actions ----------
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
                label: tr('WHAT SHOULD I DO?'),
                icon: Icons.checklist,
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            RecommendationsScreen(result: result)))),

            // ---------- Monitor ----------
            SectionHeader(tr('Monitor')),
            AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final m in knowledge.monitorItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          const Icon(Icons.visibility_outlined,
                              size: 16, color: AppColors.pine),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(tr(m),
                                  style: const TextStyle(
                                      fontSize: 13.5, height: 1.4))),
                        ]),
                      ),
                  ]),
            ),

            // ---------- Re-check ----------
            const SizedBox(height: Spacing.md),
            AppCard(
              color: AppColors.sky.withValues(alpha: 0.08),
              child: Row(children: [
                const Icon(Icons.event_repeat, color: AppColors.sky),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(tr(recheckLabel(knowledge)),
                        style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: AppColors.ink))),
              ]),
            ),

            // ---------- Technical details (expandable) ----------
            const SizedBox(height: Spacing.md),
            _TechnicalDetails(result: result, knowledge: knowledge),
            const SizedBox(height: Spacing.lg),
            Text(
              tr('AI guidance supports - but does not replace - your local '
                  'agricultural experts, especially when the situation is '
                  'severe or uncertain.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: Spacing.xl),
          ]),
        );
      },
    );
  }
}

class _PlantIdCard extends StatelessWidget {
  final PlantIdentification plant;
  const _PlantIdCard({required this.plant});

  @override
  Widget build(BuildContext context) {
    final mismatch = plant.status == 'MISMATCH_REQUESTED_CROP';
    // The name below always comes from what the MODEL identified - never
    // from the farmer's chip selection (which may conflict).
    return AppCard(
        padding: const EdgeInsets.all(Spacing.sm),
        color: AppColors.sage.withValues(alpha: 0.25),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Plant'),
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700)),
              Text(
                  tr(switch (plant.status) {
                    'IDENTIFIED' => plant.name,
                    'MISMATCH_REQUESTED_CROP' =>
                      'AI identified a different crop',
                    'UNCERTAIN' => 'Uncertain identification',
                    _ => 'Unknown Plant',
                  }),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.forest)),
              if (mismatch && plant.name.isNotEmpty)
                Text('${tr('Identified crop:')} ${tr(plant.name)}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.muted)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: Text(
              tr(switch (plant.status) {
                'IDENTIFIED' =>
                  '${(plant.confidence * 100).round()}% AI confidence',
                'MISMATCH_REQUESTED_CROP' => 'Check selected crop',
                'UNCERTAIN' => 'Identification not reliable',
                _ => 'Identification unavailable',
              }),
              style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ]));
  }
}

class _SeverityChip extends StatelessWidget {
  final String severity;
  const _SeverityChip({required this.severity});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.riskColor(severity);
    final label = switch (severity) {
      'NONE' => 'No visible disease',
      'LOW' => 'LOW',
      'MEDIUM' => 'MODERATE',
      'HIGH' => 'HIGH',
      'CRITICAL' => 'CRITICAL',
      _ => severity,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Spacing.badge),
          border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(severity == 'NONE' ? Icons.check_circle : Icons.pie_chart,
            size: 14, color: c),
        const SizedBox(width: 6),
        Text('${tr('Severity')}: ${trLevel(label)}',
            style: TextStyle(
                color: c,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.5)),
      ]),
    );
  }
}

class _TechnicalDetails extends StatelessWidget {
  final ImageAnalysisResult result;
  final DiseaseKnowledge knowledge;
  const _TechnicalDetails({required this.result, required this.knowledge});

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          childrenPadding:
              const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.md),
          collapsedBackgroundColor: Colors.white,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Spacing.radius)),
          title: Text(tr('View Technical Details'),
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted)),
          children: [
            _techRow(tr('Disease model status'), result.disease.modelStatus),
            _techRow(tr('Risk engine'), 'RULE_BASED_V1'),
            _techRow(tr('Prediction model'), result.futureRisk.modelType),
            _techRow(tr('Crop'), tr(knowledge.crop.displayName)),
            const SizedBox(height: 8),
            Text(
              tr('How this works: AgriSentry AI combined the leaf image, '
                  'weather, sensor readings and your recent scan history to '
                  'estimate this risk using transparent, documented rules.'),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
      );

  Widget _techRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
        ]),
      );
}
