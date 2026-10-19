import 'dart:io';

import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../services/analysis_orchestrator.dart';
import '../services/api_service.dart';
import '../services/app_services.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = ApiService();
  List<ScanHistoryItem> _items = [];
  List<StoredAnalysisSummary> _local = [];
  bool _offline = true, _loading = true;

  @override
  void initState() {
    super.initState();
    LanguageService.instance.language.addListener(_languageChanged);
    _load();
  }

  void _languageChanged() => setState(() {});

  @override
  void dispose() {
    LanguageService.instance.language.removeListener(_languageChanged);
    super.dispose();
  }

  String _spokenHistory() {
    if (_local.isEmpty && _items.isEmpty) return tr('No scans yet');
    final all = [
      ..._local.map((s) =>
          '${trDisease(s.diseaseName)}. ${trLevel(s.riskLevel)}. '
          '${(s.confidence * 100).round()}% ${tr('confidence')}. '),
      ..._items.map((item) =>
          '${trDisease(item.diseaseName)}. ${trLevel(item.riskLevel)}. '
          '${(item.confidence * 100).round()}% ${tr('confidence')}. '),
    ];
    return all.join(' ');
  }

  /// Local-first history (Master Prompt sections 5, 32):
  /// locally saved analyses always appear; backend scans are merged in when
  /// reachable, so history works with zero internet.
  Future<void> _load() async {
    setState(() => _loading = true);
    List<StoredAnalysisSummary> local = [];
    if (AppServices.isReady) {
      local = await AppServices.instance.analysis.historySummary();
    }
    List<ScanHistoryItem> remote = [];
    var offline = true;
    try {
      if (AppConfig.dataMode != 'simulated') {
        remote = await _api.history();
        offline = false;
      }
    } catch (_) {
      offline = true;
    }
    final localIds = local.map((e) => e.serverScanId).toSet();
    final merged = [
      ...remote.where((r) => !localIds.contains(r.scanId)),
    ];
    if (!mounted) return;
    setState(() {
      _local = local;
      _items = merged;
      _offline = offline;
      _loading = false;
    });
  }

  String _dateLabel(DateTime t) =>
      t.toIso8601String().substring(0, 16).replaceFirst('T', ' ');

  /// Opens a locally stored analysis fully offline - no backend needed.
  Future<void> _openLocalDetail(StoredAnalysisSummary s) async {
    Map<String, dynamic>? stored;
    if (AppServices.isReady) {
      stored = await AppServices.instance.db.analysisById(s.localId);
    }
    if (!mounted) return;
    if (stored == null) return;
    final result = AnalysisOrchestrator.resultFromStoredMap(stored);
    File? imageFile;
    if (s.imagePath != null && await File(s.imagePath!).exists()) {
      imageFile = File(s.imagePath!);
    }
    if (!mounted) return;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              builder: (_, controller) => ListView(
                  controller: controller,
                  padding: Spacing.page,
                  children: [
                    Center(
                        child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                                color: AppColors.sage,
                                borderRadius: BorderRadius.circular(4)))),
                    const SizedBox(height: 16),
                    Text(trDisease(result.disease.name),
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.forest)),
                    const SizedBox(height: 4),
                    Text(
                        '${_dateLabel(s.timestamp)}  ·  ${(result.disease.confidence * 100).round()}% ${tr('confidence')}',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(children: [
                      RiskBadge(result.risk.level),
                      const SizedBox(width: 10),
                      Text('${tr('Risk score')}: ${result.risk.score}/100',
                          style: const TextStyle(color: AppColors.muted)),
                    ]),
                    if (result.risk.factors.isNotEmpty) ...[
                      SectionHeader(tr('Why')),
                      for (final f in result.risk.factors)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('• ${tr(f)}',
                                style: const TextStyle(color: AppColors.ink))),
                    ],
                    if (result.explanation.summary.isNotEmpty) ...[
                      SectionHeader(tr('AI Explanation')),
                      Text(tr(result.explanation.summary),
                          style: const TextStyle(
                              color: AppColors.muted, height: 1.5)),
                    ],
                    if (result.recommendation.categories.doNow.isNotEmpty) ...[
                      SectionHeader(tr('What to do')),
                      for (final r in result.recommendation.categories.doNow)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('• ${tr(r.title)}: ${tr(r.detail)}',
                                style: const TextStyle(
                                    color: AppColors.ink, height: 1.4))),
                    ],
                    if (imageFile != null) ...[
                      SectionHeader(tr('Leaf photo')),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Spacing.radius),
                        child: Image.file(imageFile,
                            cacheWidth: 900,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover),
                      ),
                    ],
                  ])));
  }

  Future<void> _openDetail(ScanHistoryItem item) async {
    Map<String, dynamic>? detail;
    try {
      detail = await _api.scanDetail(item.scanId);
    } catch (_) {/* offline: show basics only */}
    if (!mounted) return;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              builder: (_, controller) {
                final factors = (detail?['risk_factors'] as List?)
                        ?.cast<String>() ??
                    const <String>[];
                final explanation =
                    detail?['explanation'] as Map<String, dynamic>?;
                final recs =
                    detail?['recommendations'] as Map<String, dynamic>?;
                final cats = (recs?['categories'] as Map<String, dynamic>?) ??
                    const {};
                final doNow = (cats['do_now'] as List?) ?? const [];
                return ListView(
                    controller: controller,
                    padding: Spacing.page,
                    children: [
                      Center(
                          child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                  color: AppColors.sage,
                                  borderRadius: BorderRadius.circular(4)))),
                      const SizedBox(height: 16),
                      Text(trDisease(item.diseaseName),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppColors.forest)),
                      const SizedBox(height: 4),
                      Text(
                          '${item.dateLabel}  ·  ${(item.confidence * 100).round()}% ${tr('confidence')}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 12),
                      Row(children: [
                        RiskBadge(item.riskLevel),
                        const SizedBox(width: 10),
                        Text('${tr('Risk score')}: ${item.riskScore}/100',
                            style:
                                const TextStyle(color: AppColors.muted)),
                      ]),
                      if (factors.isNotEmpty) ...[
                        SectionHeader(tr('Why')),
                        for (final f in factors)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text('• ${tr(f)}',
                                  style: const TextStyle(
                                      color: AppColors.ink))),
                      ],
                      if (explanation?['summary'] != null) ...[
                        SectionHeader(tr('AI Explanation')),
                        Text(tr(explanation!['summary'] as String),
                            style: const TextStyle(
                                color: AppColors.muted, height: 1.5)),
                      ],
                      if (doNow.isNotEmpty) ...[
                        SectionHeader(tr('What to do')),
                        for (final r in doNow)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                  '• ${tr((r as Map)['title'] as String)}: ${tr(r['detail'] as String)}',
                                  style: const TextStyle(
                                      color: AppColors.ink, height: 1.4))),
                      ],
                    ]);
              },
            ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(tr('History')),
          actions: [
            SpeakButton(text: _spokenHistory),
            const LanguageToggleButton(),
          ],
        ),
        body: _loading
            ? LoadingView(tr('Loading past scans...'))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: Spacing.page, children: [
                  if (_offline) const OfflineBanner(),
                  const SizedBox(height: Spacing.sm),
                  if (_local.isEmpty && _items.isEmpty)
                    EmptyView(
                        title: tr('No scans yet'),
                        message: tr(
                            'Scan your first leaf to start building history.'))
                  else ...[
                    // Local-first: analyses saved on this device.
                    for (final s in _local)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.sm),
                        child: AppCard(
                            onTap: () => _openLocalDetail(s),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: AppColors.sage
                                        .withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(14)),
                              child: Text(s.cropName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.forest)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(trDisease(s.diseaseName),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15.5)),
                                    Text(
                                        '${s.cropDisplayName} · ${_dateLabel(s.timestamp)}',
                                        style: const TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 12)),
                                  ])),
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    RiskBadge(s.riskLevel),
                                    const SizedBox(height: 4),
                                    Text(tr(s.syncLabelKey),
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: s.syncStatus
                                                    .toUpperCase() ==
                                                    'SYNCED'
                                                ? AppColors.pine
                                                : AppColors.amber)),
                                  ]),
                            ])),
                      ),
                    // Backend history (when reachable).
                    for (final it in _items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.sm),
                        child: AppCard(
                            onTap: () => _openDetail(it),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: AppColors.sage.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(14)),
                                child: const Icon(Icons.eco,
                                    color: AppColors.pine),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(trDisease(it.diseaseName),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15.5)),
                                    Text(it.dateLabel,
                                        style: const TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 12)),
                                  ])),
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    RiskBadge(it.riskLevel),
                                    const SizedBox(height: 4),
                                    Text('${(it.confidence * 100).round()}%',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.muted)),
                                  ]),
                            ])),
                      ),
                  ],
                ]),
              ),
      );
}
