import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../utils/crop_intelligence.dart';
import '../widgets/common.dart';

class AnalyticsScreen extends StatelessWidget {
  final List<ScanHistoryItem> items;
  const AnalyticsScreen({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final a = HistoryAnalytics.from(items);
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.instance.language,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          title: Text(tr('Analytics')),
          actions: const [LanguageToggleButton()],
        ),
        body: ListView(padding: Spacing.page, children: [
          Text(
              tr('Calculated only from scans stored on this device or backend.'),
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: Spacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Spacing.sm,
            crossAxisSpacing: Spacing.sm,
            childAspectRatio: 1.35,
            children: [
              _stat(tr('Total scans'), '${a.totalScans}',
                  Icons.document_scanner),
              _stat(tr('Healthy scans'), '${a.healthyScans}',
                  Icons.check_circle_outline),
              _stat(tr('Disease detections'), '${a.diseaseDetections}',
                  Icons.coronavirus_outlined),
              _stat(tr('Average confidence'),
                  '${(a.averageConfidence * 100).round()}%', Icons.verified),
            ],
          ),
          const SizedBox(height: Spacing.md),
          AppCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(tr('Most detected condition'),
                  style: const TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                  a.mostDetected == null
                      ? tr('No scans yet')
                      : trDisease(a.mostDetected!),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.forest)),
              const SizedBox(height: 12),
              Text('${tr('Average risk')} ${a.averageRisk.round()}/100',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.pine, size: 20),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.forest)),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );
}
