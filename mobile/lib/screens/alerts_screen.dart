import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/farm_store.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../utils/crop_intelligence.dart';
import '../widgets/common.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  int _sev(String s) {
    switch (s) {
      case 'CRITICAL':
        return 3;
      case 'HIGH':
        return 2;
      case 'MEDIUM':
        return 1;
      default:
        return 0;
    }
  }

  String _spokenAlerts() => _alerts()
      .map((a) => '${tr(a.title)}. ${tr(a.body)}')
      .join(' ');

  List<AlertItem> _alerts() {
    final store = FarmStore.instance;
    final env = store.environment.value;
    final weather = store.weather.value;
    final scan = store.lastScan.value;
    // Data integrity (audit): an empty farm shows NO fabricated sample
    // alerts - the empty state below explains what will appear here.
    return alertsFromFarm(
      env: env,
      weather: weather,
      scan: scan,
      backendReachable: store.backendReachable.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _alerts()
      ..sort((a, b) => _sev(b.severity).compareTo(_sev(a.severity)));
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.instance.language,
      builder: (context, language, _) => Scaffold(
      appBar: AppBar(
        title: Text(tr('Alerts')),
        actions: [
          SpeakButton(text: _spokenAlerts),
          const LanguageToggleButton(),
        ],
      ),
      body: alerts.isEmpty
          ? EmptyView(
              title: tr('No alerts'),
              message: tr('Everything looks fine on your farm right now.'))
          : ListView(padding: Spacing.page, children: [
              if (FarmStore.instance.environment.value?.source == 'SIMULATED')
                const SimulatedBanner(),
              const SizedBox(height: Spacing.sm),
              for (final a in alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: AppCard(
                    color: a.severity == 'HIGH'
                        ? AppColors.danger.withValues(alpha: 0.06)
                        : Colors.white,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: AppColors.riskColor(a.severity)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12)),
                            child: Icon(
                                a.type == 'weather'
                                    ? Icons.cloud_outlined
                                    : a.type == 'environment'
                                        ? Icons.thermostat
                                        : Icons.warning_amber_rounded,
                                color: AppColors.riskColor(a.severity)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(tr(a.title),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15.5))),
                                  RiskBadge(a.severity),
                                ]),
                                const SizedBox(height: 4),
                                Text(tr(a.body),
                                    style: const TextStyle(
                                        color: AppColors.muted, height: 1.5)),
                              ])),
                        ]),
                  ),
                ),
            ]),
    ));
  }
}
