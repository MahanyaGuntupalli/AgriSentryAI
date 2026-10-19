import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class WhyScreen extends StatelessWidget {
  final ImageAnalysisResult result;
  const WhyScreen({super.key, required this.result});

  IconData _icon(String? name) {
    switch (name) {
      case 'leaf':
        return Icons.eco;
      case 'thermometer':
        return Icons.thermostat;
      case 'cloud':
        return Icons.cloud_outlined;
      case 'clock':
        return Icons.history;
      case 'assessment':
        return Icons.assessment_outlined;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'check':
        return Icons.check_circle_outline;
      case 'build':
        return Icons.build_outlined;
      case 'calendar':
        return Icons.calendar_today_outlined;
      case 'shield':
        return Icons.shield_outlined;
      case 'eye':
        return Icons.visibility_outlined;
      case 'person':
        return Icons.person_outline;
      case 'help':
        return Icons.help_outline;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppLanguage>(
        valueListenable: LanguageService.instance.language,
        builder: (context, lang, _) => Scaffold(
          appBar: AppBar(
            title: Text(tr('Why?')),
            actions: [
              SpeakButton(text: () => spokenWhy(result)),
              const LanguageToggleButton(),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(padding: Spacing.page, children: [
            AppCard(
              color: AppColors.forest,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome,
                          color: AppColors.leafLight, size: 20),
                      const SizedBox(width: 8),
                      Text(tr('WHY THIS RISK?'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6)),
                    ]),
                    const SizedBox(height: 10),
                    Text(tr(result.explanation.summary),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            height: 1.5)),
                  ]),
            ),
            SectionHeader(tr('Contributing Factors')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in result.risk.factors)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.amber.withValues(alpha: 0.4))),
                  child: Text(tr(f),
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF9A6B1A),
                          fontWeight: FontWeight.w700)),
                ),
            ]),
            SectionHeader(tr('The Details')),
            for (final s in result.explanation.sections)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: AppCard(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.sage.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(_icon(s.icon), color: AppColors.pine),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(tr(s.title),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.forest,
                                    fontSize: 15.5)),
                            const SizedBox(height: 4),
                            Text(tr(s.body),
                                style: const TextStyle(
                                    color: AppColors.muted, height: 1.5)),
                          ])),
                    ])),
              ),
            if (result.explanation.confidence != null) ...[
              SectionHeader(tr('AI Confidence')),
              AppCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(sureLabel((result.explanation.confidence! * 100).round()),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: AppColors.forest)),
                    const SizedBox(height: 8),
                    ConfidenceBar(
                        (result.explanation.confidence! * 100).round()),
                  ])),
            ],
            const SizedBox(height: Spacing.xl),
          ]),
        ),
      );
}
