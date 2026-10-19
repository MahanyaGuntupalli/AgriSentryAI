import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/app_services.dart';
import '../services/farm_store.dart';
import '../services/sync_service.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../utils/app_routes.dart';
import '../widgets/common.dart';
import 'legal_screen.dart';

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
        valueListenable: LanguageService.instance.language,
        builder: (context, language, _) => AnimatedBuilder(
        animation: Listenable.merge([
          FarmStore.instance.environment,
          FarmStore.instance.backendReachable,
        ]),
        builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('Device Status')),
          actions: [
            SpeakButton(
                text: () => tr(
                    'Device status is active. Simulated sensor feed is connected.')),
            const LanguageToggleButton(),
          ],
        ),
        body: ListView(padding: Spacing.page, children: [
          const SizedBox(height: Spacing.md),

          // ---------- Synchronization (Master Prompt sections 6, 7, 16) ----------
          if (AppServices.isReady) ...[
            SectionHeader(tr('Synchronization')),
            AppCard(
              child: Column(children: [
                AnimatedBuilder(
                  animation: Listenable.merge([
                    AppServices.instance.sync.status,
                    AppServices.instance.sync.pendingCount,
                    AppServices.instance.sync.lastSynced,
                  ]),
                  builder: (context, _) {
                    final status = AppServices.instance.sync.status.value;
                    final pending = AppServices.instance.sync.pendingCount.value;
                    final last = AppServices.instance.sync.lastSynced.value;
                    final (color, icon) = switch (status) {
                      SyncStatus.synced => (AppColors.pine, Icons.cloud_done_outlined),
                      SyncStatus.pending => (AppColors.amber, Icons.cloud_upload_outlined),
                      SyncStatus.syncing => (AppColors.sky, Icons.sync),
                      SyncStatus.offline => (AppColors.danger, Icons.cloud_off_outlined),
                    };
                    return Column(children: [
                      Row(children: [
                        Icon(icon, color: color, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr(AppServices.instance.sync.statusLabelKey),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: color)),
                                Text(
                                  pending == 0
                                      ? tr('All analyses are saved and synced.')
                                      : '$pending ${tr('analyses waiting to sync')} - ${tr('saved safely on this device. Will sync automatically when internet is available.')}',
                                  style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12.5,
                                      height: 1.4),
                                ),
                                if (last != null)
                                  Text(
                                      '${tr('Last sync')}: ${last.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}',
                                      style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 11)),
                              ]),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () =>
                            AppServices.instance.sync.syncNow(),
                        icon: const Icon(Icons.sync, size: 18),
                        label: Text(tr('Sync now')),
                      ),
                    ]);
                  },
                ),
              ]),
            ),
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.sage.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.offline_pin_outlined,
                    size: 18, color: AppColors.pine),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        tr('Offline-first: analyses are always saved on this '
                            'device first and synced when internet returns.'),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.ink, height: 1.4))),
              ]),
            ),
          ],

          // ---------- Device status (existing) ----------
          SectionHeader(tr('Connection')),
          AppCard(
              child: Column(children: [
            const Icon(Icons.wifi_tethering, size: 44, color: AppColors.pine),
            const SizedBox(height: 10),
            Text(FarmStore.instance.environment.value?.deviceId ?? 'UNKNOWN',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                  color: (FarmStore.instance.backendReachable.value
                          ? AppColors.leaf
                          : AppColors.amber)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(Spacing.badge)),
              child: Text(tr(FarmStore.instance.backendReachable.value
                  ? 'SYNCED'
                  : 'OFFLINE / NOT CONFIRMED'),
                  style: TextStyle(
                      color: FarmStore.instance.backendReachable.value
                          ? AppColors.pine
                          : AppColors.amber,                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.8)),
            ),
          ])),
          AppCard(
              child: Column(children: [
            _Row(
                tr('Status'),
                tr(FarmStore.instance.backendReachable.value
                    ? 'Backend reachable'
                    : 'Live connection not confirmed'),
                Icons.cloud_done_outlined),
            const Divider(height: 20),
            _Row(tr('Data source'),
                tr(FarmStore.instance.environment.value?.source == 'REAL'
                    ? 'LIVE SENSOR DATA'
                    : 'SIMULATED (not live ESP32)'),
                Icons.science_outlined),
            const Divider(height: 20),
            _Row(tr('Backend'), AppConfig.apiBaseUrl, Icons.dns_outlined),
          ])),
          SectionHeader(tr('Sensors')),
          AppCard(
              child: Column(children: [
            _Row(tr('Temperature / Humidity'),
                _sensorStatus('Temperature / Humidity'), Icons.thermostat),
            const Divider(height: 20),
            _Row(tr('Soil moisture'), _sensorStatus('Soil moisture'), Icons.grass),
            const Divider(height: 20),
            _Row(tr('Light (LDR)'), _sensorStatus('Light (LDR)'),
                Icons.wb_sunny_outlined),
          ])),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.sage.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14)),
            child: Text(
              tr('When the real ESP32 kit is connected, this screen shows LIVE ESP32 data with no app changes. The device must send readings to your PC\'s LAN IP (e.g. http://192.168.1.20:8000) - never localhost.'),
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.ink, height: 1.5),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          SectionHeader(tr('Legal')),
          AppCard(
              child: Column(children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.policy_outlined, color: AppColors.pine),
              title: Text(tr('Privacy Policy'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
              onTap: () => Navigator.push(
                  context, fadeSlideTo(const PrivacyPolicyScreen())),
            ),
            const Divider(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading:
                  const Icon(Icons.description_outlined, color: AppColors.pine),
              title: Text(tr('Terms and Conditions'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
              onTap: () =>
                  Navigator.push(context, fadeSlideTo(const TermsScreen())),
            ),
          ])),
          const SizedBox(height: Spacing.xl),
        ]),
      )));
}

String _sensorStatus(String label) =>
    FarmStore.instance.environment.value == null ? tr('NO DATA') : tr('AVAILABLE');

class _Row extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _Row(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: AppColors.pine),
        const SizedBox(width: 12),
        Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700))),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 12.5))),
      ]);
}
