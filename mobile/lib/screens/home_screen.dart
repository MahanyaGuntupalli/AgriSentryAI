import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/crop_disease_knowledge.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../services/analysis_orchestrator.dart';
import '../services/api_service.dart';
import '../services/app_services.dart';
import '../services/farm_store.dart';
import '../services/mock_data.dart';
import '../services/sync_service.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../utils/app_routes.dart';
import '../utils/crop_intelligence.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'alerts_screen.dart';
import 'analytics_screen.dart';
import 'device_screen.dart';
import 'history_screen.dart';
import 'recommendations_screen.dart';
import 'risk_screen.dart';
import 'scan_screen.dart';
import 'sensors_screen.dart';
import 'weather_screen.dart';
import 'why_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  EnvironmentalData? _env;
  WeatherData? _weather;
  ImageAnalysisResult? _lastScan;
  List<ScanHistoryItem> _history = const [];
  StoredAnalysisSummary? _latestLocal;
  bool _offline = true, _loading = true;
  String _farmer = 'Farmer';
  CropType? _crop;

  /// Null when the farmer has never selected a crop - drives the neutral
  /// 'Your Crop' header state (no silent tomato assumption).
  String? _lastCropSelection;

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

  /// Local-first home loading (Master Prompt sections 5, 23):
  /// stored analyses + cached environment render instantly; the backend
  /// refreshes them when reachable; demo data only in simulated mode.
  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _farmer = prefs.getString('farmer_name') ?? tr('Farmer');
    _lastCropSelection = prefs.getString('selected_crop');
    _crop = CropType.tryParse(_lastCropSelection);
    final store = FarmStore.instance;

    // 1. Local state first - always available offline.
    if (AppServices.isReady) {
      final summaries =
          await AppServices.instance.analysis.historySummary(limit: 20);
      if (summaries.isNotEmpty) {
        _latestLocal = summaries.first;
        final stored = await AppServices.instance.db
            .analysisById(_latestLocal!.localId);
        if (stored != null) {
          _lastScan ??= AnalysisOrchestrator.resultFromStoredMap(stored);
        }
      }
    }

    if (AppConfig.dataMode == 'simulated') {
      setState(() {
        _env = MockData.environment();
        _weather = MockData.weather();
        _lastScan = store.lastScan.value ?? MockData.sampleAnalysis();
        _history = MockData.history();
        _offline = false;
        _loading = false;
      });
      _publish();
      return;
    }
    try {
      // Parallel fetches (performance audit): sensors, weather and history
      // are independent requests - running them concurrently cuts Home's
      // cold-load wait to the slowest single call instead of their sum.
      final results = await Future.wait<Map<String, dynamic>>([
        _api.latestSensors().then((v) => {'env': v}),
        _api.currentWeather().then((v) => {'weather': v}),
      ]);
      final env = results[0]['env'] as EnvironmentalData;
      final weather = results[1]['weather'] as WeatherData;
      ImageAnalysisResult? scan = store.lastScan.value ?? _lastScan;
      List<ScanHistoryItem> history = const [];
      try {
        history = await _api.history(limit: 40);
        if (history.isNotEmpty && scan == null) {
          scan = ImageAnalysisResult.fromJson(
              await _api.scanDetail(history.first.scanId));
        }
      } catch (_) {}
      setState(() {
        _env = env;
        _weather = weather;
        _lastScan = scan;
        _history = history;
        _offline = false;
      });
    } catch (_) {
      // Offline: show ONLY locally cached REAL values. Data-integrity rule:
      // mock/demo data is never substituted silently on the Home dashboard -
      // missing data stays unavailable until the backend returns.
      setState(() {
        _env = store.environment.value;
        _weather = store.weather.value;
        _lastScan = store.lastScan.value ?? _lastScan;
        _history = store.history.value;
        _offline = true;
      });
    }
    _publish();
    if (mounted) setState(() => _loading = false);
  }

  void _publish() {
    final store = FarmStore.instance;
    store.environment.value = _env;
    store.weather.value = _weather;
    if (_lastScan != null) store.lastScan.value = _lastScan;
    store.history.value = _history;
    store.backendReachable.value = !_offline;
    store.lastSynced.value = DateTime.now();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : 'Good evening';
  }

  String _spoken() {
    final scan = _lastScan;
    if (scan == null) return tr('No crop analysis is available yet.');
    return '${tr(scan.explanation.summary)} ${scan.risk.factors.map(tr).join(' ')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          body: SafeArea(child: LoadingView(tr('Loading your farm...'))));
    }
    final scan = _lastScan;
    final health = cropHealthFromScan(scan);
    final healthLabel =
        scan == null ? tr('Not analyzed') : healthLabelForScore(health);
    final farmerName = _farmer == 'Farmer' ? tr('Farmer') : _farmer;
    final alerts = alertsFromFarm(
      env: _env,
      weather: _weather,
      scan: scan,
      backendReachable: !_offline,
    );
    final severity = estimatedSeverity(scan);
    // Dynamic crop line: neutral until the farmer actually selects a crop.
    final hasSelectedCrop = _crop != null;
    final cropLine = hasSelectedCrop
        ? tr('Your ${_crop!.displayName} Field')
        : '${tr('Your Crop')} · ${tr('Add or scan a crop to get started')}';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: Spacing.page, children: [
            if (_offline)
              const OfflineBanner()
            else if (_env?.source == 'SIMULATED')
              const SimulatedBanner(),
            FadeSlideIn(
              child: PremiumFarmHeader(
                greeting: tr(_greeting),
                farmer: farmerName,
                alertCount: alerts.length,
                spokenSummary: _spoken,
                cropLine: cropLine,
                onAlerts: () => Navigator.push(
                  context,
                  fadeSlideTo(const AlertsScreen()),
                ),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            FadeSlideIn(
              delay: const Duration(milliseconds: 70),
              child: Row(children: [
                Expanded(
                  child: ConnectionPill(
                    connected: !_offline,
                    simulated: _env?.source == 'SIMULATED',
                    updated: _env == null
                        ? null
                        : '${tr('Last updated:')} ${dataFreshnessLabel(_env!.timestamp)}',
                  ),
                ),
                if (AppServices.isReady) const _SyncStatusChip(),
              ]),
            ),
            const SizedBox(height: Spacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 140),
              child: AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('How healthy is my crop right now?'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.forest)),
                    const SizedBox(height: 14),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          HealthRing(
                              percent: scan == null ? 0 : health,
                              label: tr(healthLabel)),
                          const SizedBox(width: Spacing.md),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tr('Crop'),
                                      style: const TextStyle(
                                          color: AppColors.muted, fontSize: 12)),
                                  Text(
                                      hasSelectedCrop
                                          ? tr(_crop!.displayName)
                                          : tr('Not selected yet'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18)),
                                  const SizedBox(height: 8),
                                  Text(tr('Condition'),
                                      style: const TextStyle(
                                          color: AppColors.muted, fontSize: 12)),
                                  Text(
                                      scan == null
                                          ? tr('Add or scan a crop to get started')
                                          : trDisease(scan.disease.name),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: AppColors.forest)),
                                  if (scan != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                        '${confidenceLabel(scan.disease.confidencePct)}  ·  ${tr('Severity')} ${trLevel(severity)}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted)),
                                  ],
                                ]),
                          ),
                        ]),
                  ]),
            )),
            const SizedBox(height: Spacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 200),
              child: AppCard(
              child: scan == null
                  // Neutral pre-scan state (audit): no risk number before a
                  // scan exists - never show a default LOW/HIGH gauge.
                  ? Row(children: [
                      const Icon(Icons.radar,
                          size: 40, color: AppColors.sage),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('CURRENT ENVIRONMENTAL RISK'),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.muted,
                                      letterSpacing: 0.4)),
                              const SizedBox(height: 6),
                              Text(tr('Waiting for scan'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: AppColors.muted)),
                              const SizedBox(height: 4),
                              Text(
                                  tr(
                                      'Scan a leaf to calculate risk from image + environment.'),
                                  style: const TextStyle(
                                      color: AppColors.muted, height: 1.4)),
                            ]),
                      ),
                    ])
                  : Row(children: [
                RiskGauge(
                    score: scan.risk.score,
                    level: scan.risk.level),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(tr('CURRENT ENVIRONMENTAL RISK'),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.muted,
                            letterSpacing: 0.4)),
                    const SizedBox(height: 8),
                    Text(tr('Driven by'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.forest)),
                    const SizedBox(height: 4),
                    for (final f in scan.risk.factors.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• ${tr(f)}',
                              style: const TextStyle(
                                  fontSize: 12.5, height: 1.35)),
                        ),
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.push(
                                  context, fadeSlideTo(const RiskScreen())),
                          child: Text(tr('VIEW RISK')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.push(
                                  context, fadeSlideTo(WhyScreen(result: scan))),
                          child: Text(tr('WHY?')),
                        ),
                      ],
                    ),
                  ]),
                ),
              ]),
            )),
            SectionHeader(tr('Environment'),
                actionLabel: tr('Details'),
                onAction: () =>
                    Navigator.push(context, fadeSlideTo(const SensorsScreen()))),
            if (_env == null)
              AppCard(
                child: Row(children: [
                  const Icon(Icons.sensors_off,
                      size: 28, color: AppColors.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(tr('Sensor data unavailable'),
                        style: const TextStyle(
                            color: AppColors.muted, height: 1.4)),
                  ),
                ]),
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Spacing.sm,
                crossAxisSpacing: Spacing.sm,
                childAspectRatio: 0.98,
                children: [
                  MetricCard(
                    icon: Icons.thermostat,
                    label: tr('Temperature'),
                    value: _env!.temperature.toStringAsFixed(0),
                    unit: '°C',
                    color: AppColors.amber,
                    status: sensorBand('temp', _env!.temperature),
                    hint: sensorContext('temp', _env!.temperature),
                  ),
                  MetricCard(
                    icon: Icons.water_drop_outlined,
                    label: tr('Humidity'),
                    value: _env!.humidity.toStringAsFixed(0),
                    unit: '%',
                    color: AppColors.sky,
                    status: sensorBand('humidity', _env!.humidity),
                    hint: sensorContext('humidity', _env!.humidity),
                  ),
                  MetricCard(
                    icon: Icons.grass,
                    label: tr('Soil Moisture'),
                    value: _env!.soilMoisture.toStringAsFixed(0),
                    unit: '%',
                    color: AppColors.soil,
                    status: sensorBand('soil', _env!.soilMoisture),
                    hint: sensorContext('soil', _env!.soilMoisture),
                  ),
                  MetricCard(
                    icon: Icons.wb_sunny_outlined,
                    label: tr('Light'),
                    value: _env!.light.toStringAsFixed(0),
                    unit: 'lux',
                    color: AppColors.amber,
                    status: sensorBand('light', _env!.light),
                    hint: sensorContext('light', _env!.light),
                  ),
                ],
              ),
            if (_env?.leafWetness != null) ...[
              const SizedBox(height: Spacing.sm),
              MetricCard(
                icon: Icons.opacity,
                label: tr('Leaf Wetness'),
                value: _env!.leafWetness!.toStringAsFixed(0),
                unit: '%',
                color: AppColors.sky,
                hint: 'Optional sensor reading from the field kit.',
              ),
            ],
            SectionHeader(tr('Weather Intelligence'),
                actionLabel: tr('Full forecast'),
                onAction: () =>
                    Navigator.push(context, fadeSlideTo(const WeatherScreen()))),
            if (_weather == null)
              AppCard(
                onTap: () =>
                    Navigator.push(context, fadeSlideTo(const WeatherScreen())),
                child: Row(children: [
                  const Icon(Icons.cloud_off,
                      size: 28, color: AppColors.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(tr('Weather data unavailable'),
                        style: const TextStyle(
                            color: AppColors.muted, height: 1.4)),
                  ),
                ]),
              )
            else
              AppCard(
                onTap: () =>
                    Navigator.push(context, fadeSlideTo(const WeatherScreen())),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                            (_weather!.condition ?? '')
                                    .toLowerCase()
                                    .contains('rain')
                                ? Icons.water_drop
                                : Icons.wb_sunny,
                            color: AppColors.sky,
                            size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_weather!.temperature?.toStringAsFixed(0) ?? '--'}°C  ·  ${tr(_weather!.condition ?? '')}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                        SourceChip(_weather!.source),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        '${tr('Humidity')} ${_weather!.humidity?.toStringAsFixed(0) ?? '--'}%  ·  ${tr('Rainfall')} ${_weather!.rainfall?.toStringAsFixed(1) ?? '0'} mm',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 13),
                      ),
                      if (_weather!.forecastTrend == 'WORSENING') ...[
                        const SizedBox(height: 10),
                        Text(
                          tr('HIGH HUMIDITY and rain can favor disease development. This is an estimate, not a guarantee.'),
                          style: const TextStyle(
                              fontSize: 13, height: 1.4, color: AppColors.ink),
                        ),
                      ],
                    ]),
              ),
            if (scan != null) ...[
              SectionHeader(tr('ESTIMATED FUTURE RISK')),
              AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  FutureRiskChart(scan.futureRisk.points),
                  const SizedBox(height: 10),
                  RiskTimeline(scan.futureRisk.points),
                  const SizedBox(height: 8),
                  Text(
                      tr(scan.futureRisk.disclaimer.isEmpty
                          ? estimatedRiskNote()
                          : scan.futureRisk.disclaimer),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted, height: 1.4)),
                ]),
              ),
              SectionHeader(tr('Multimodal analysis')),
              AppCard(
                child: MultimodalStrip(
                  hasSensors: scan.environment != null || _env != null,
                  hasWeather: scan.weather != null || _weather != null,
                  hasHistory: _history.isNotEmpty,
                ),
              ),
            ],
            if (_history.isNotEmpty) ...[
             SectionHeader(
               tr('Recent scans'),
               actionLabel: tr('View all'),
               onAction: () => Navigator.push(
                 context,
                 fadeSlideTo(const HistoryScreen()),
               ),
             ),
             ..._history.take(3).map((item) => _RecentScanTile(item: item)),
            ],
            SectionHeader(tr('Quick actions')),
            Row(children: [
              Expanded(
                  child: QuickAction(
                      icon: Icons.document_scanner_outlined,
                      label: tr('Scan Crop'),
                      onTap: () => Navigator.push(
                          context, fadeSlideTo(const ScanScreen())))),
              const SizedBox(width: 8),
              Expanded(
                  child: QuickAction(
                      icon: Icons.history,
                      label: tr('History'),
                      onTap: () => Navigator.push(
                          context, fadeSlideTo(const HistoryScreen())))),
              const SizedBox(width: 8),
              Expanded(
                  child: QuickAction(
                      icon: Icons.sensors,
                      label: tr('Sensors'),
                      onTap: () => Navigator.push(
                          context, fadeSlideTo(const SensorsScreen())))),
              const SizedBox(width: 8),
              Expanded(
                  child: QuickAction(
                      icon: Icons.cloud_outlined,
                      label: tr('Weather'),
                      onTap: () => Navigator.push(
                          context, fadeSlideTo(const WeatherScreen())))),
            ]),
            const SizedBox(height: Spacing.md),
            PrimaryButton(
                label: tr('SCAN LEAF'),
                icon: Icons.document_scanner_outlined,
                onPressed: () =>
                    Navigator.push(context, fadeSlideTo(const ScanScreen()))),
            if (scan != null) ...[
              const SizedBox(height: Spacing.sm),
              PrimaryButton(
                  label: tr('WHAT SHOULD I DO?'),
                  icon: Icons.checklist,
                  color: AppColors.pine,
                  onPressed: () => Navigator.push(context,
                      fadeSlideTo(RecommendationsScreen(result: scan)))),
            ],
            SectionHeader(tr('AI Insight')),
            AppCard(
              color: AppColors.forest,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: AppColors.leafLight, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                      tr(scan?.explanation.summary ??
                          'Scan a leaf to get your first AI insight.'),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15, height: 1.45),
                    )),
                  ]),
            ),
            SectionHeader(tr('Recent Alert'),
                actionLabel: tr('All alerts'),
                onAction: () =>
                    Navigator.push(context, fadeSlideTo(const AlertsScreen()))),
            if (alerts.isEmpty)
              AppCard(
                  child: Text(
                      tr('Everything looks fine on your farm right now.')))
            else
              AppCard(
                onTap: () =>
                    Navigator.push(context, fadeSlideTo(const AlertsScreen())),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.riskColor(alerts.first.severity)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(tr(alerts.first.body),
                          style: const TextStyle(fontSize: 14, height: 1.4))),
                ]),
              ),
            if (_history.isNotEmpty)
              SectionHeader(tr('Analytics'),
                  actionLabel: tr('Details'),
                  onAction: () => Navigator.push(
                      context, fadeSlideTo(AnalyticsScreen(items: _history)))),
            const SizedBox(height: Spacing.xl),
          ]),
        ),
      ),
    );
  }
}

class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SyncStatus>(
        valueListenable: AppServices.instance.sync.status,
        builder: (context, status, _) {
          final (color, icon, label) = switch (status) {
            SyncStatus.synced => (
                AppColors.pine,
                Icons.cloud_done_outlined,
                'Synced',
              ),
            SyncStatus.pending => (
                AppColors.amber,
                Icons.cloud_upload_outlined,
                'Sync pending',
              ),
            SyncStatus.syncing => (
                AppColors.sky,
                Icons.sync,
                'Syncing...',
              ),
            SyncStatus.offline => (
                AppColors.danger,
                Icons.cloud_off_outlined,
                'Offline - saved on device',
              ),
          };
          return InkWell(
            onTap: () => Navigator.push(
                context, fadeSlideTo(const DeviceScreen())),
            borderRadius: BorderRadius.circular(Spacing.badge),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Spacing.badge),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
                Text(tr(label),
                    style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3)),
              ]),
            ),
          );
        },
      );
}

class _RecentScanTile extends StatelessWidget {
  final ScanHistoryItem item;
  const _RecentScanTile({required this.item});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: AppCard(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.sm),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.sage,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.eco_outlined, color: AppColors.pine),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trDisease(item.diseaseName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.forest,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.dateLabel,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RiskBadge(item.riskLevel),
                  const SizedBox(height: 3),
                  Text(
                    '${item.confidence.round()}%',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}