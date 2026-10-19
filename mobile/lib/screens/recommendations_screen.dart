import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class RecommendationsScreen extends StatefulWidget {
  final ImageAnalysisResult result;
  const RecommendationsScreen({super.key, required this.result});
  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  @override
  Widget build(BuildContext context) {
    final rec = widget.result.recommendation;
    final cats = [
      ('DO NOW', Icons.bolt, rec.categories.doNow),
      ('MANAGE', Icons.medical_services_outlined, rec.categories.manage),
      ('PREVENT', Icons.shield_outlined, rec.categories.prevent),
      ('MONITOR', Icons.visibility_outlined, rec.categories.monitor),
      ('WATER', Icons.water_drop_outlined, rec.categories.water),
      ('ENVIRONMENT', Icons.air, rec.categories.environment),
    ];
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.instance.language,
      builder: (context, lang, _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('What To Do?')),
          actions: [
            SpeakButton(text: () => spokenRecs(widget.result)),
            const LanguageToggleButton(),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(padding: Spacing.page, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.sky.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppColors.sky.withValues(alpha: 0.3))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, color: AppColors.sky, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(tr(rec.disclaimer),
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.ink,
                          height: 1.5))),
            ]),
          ),
          for (final entry in cats)
            if (entry.$3.isNotEmpty) ...[
              SectionHeader(tr(entry.$1)),
              for (var i = 0; i < entry.$3.length; i++)
                _ActionCard(
                  item: entry.$3[i],
                  onChanged: (v) =>
                      setState(() => entry.$3[i].done = v ?? false),
                ),
            ],
          const SizedBox(height: Spacing.xl),
        ]),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final RecommendationItem item;
  final ValueChanged<bool?> onChanged;
  const _ActionCard({required this.item, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.riskColor(item.urgency);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                    width: 6,
                    decoration: BoxDecoration(
                        color: c,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(Spacing.radius)))),
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: item.done ? 0.45 : 1,
                            child: Text(tr(item.title),
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15.5,
                                    color: AppColors.ink,
                                    decoration: item.done
                                        ? TextDecoration.lineThrough
                                        : null)),
                          )),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: c.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(trLevel(item.urgency),
                                style: TextStyle(
                                    color: c,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(tr(item.detail),
                            style: const TextStyle(
                                color: AppColors.muted,
                                height: 1.5,
                                fontSize: 13.5)),
                      ]),
                )),
                Checkbox(
                    value: item.done,
                    activeColor: AppColors.pine,
                    onChanged: onChanged),
              ]),
        ),
      ),
    );
  }
}
