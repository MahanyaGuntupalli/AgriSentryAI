import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'device_screen.dart';

class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key});
  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  final _api = ApiService();
  List<EnvironmentalData> _readings = [];
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

  String _spokenEnvironment() {
    final latest = _readings.isNotEmpty ? _readings.last : null;
    if (latest == null) return tr('Reading sensors...');
    return '${tr('Temperature')}: ${latest.temperature}. '
        '${tr('Humidity')}: ${latest.humidity}%. '
        '${tr('Soil Moisture')}: ${latest.soilMoisture}%. '
        '${tr('Light')}: ${latest.light}.';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (AppConfig.dataMode == 'simulated') throw Exception('simulated mode');
      final latest = await _api.latestSensors();
      final hist = await _api.sensorHistory();
      setState(() {
        _readings = hist.isEmpty ? [latest] : hist;
        _offline = false;
      });
    } catch (_) {
      // Data integrity (audit section 12): no fake sensor values when the
      // ESP32/backend is unreachable. The explicit unavailable state renders
      // below instead.
      setState(() {
        _readings = const [];
        _offline = true;
      });
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final latest = _readings.isNotEmpty ? _readings.last : null;
    return Scaffold(
      appBar: AppBar(
          title: Text(tr('Environment')),
          actions: [
            SpeakButton(text: _spokenEnvironment),
            const LanguageToggleButton(),
          ]),
      body: _loading
          ? LoadingView(tr('Reading sensors...'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: Spacing.page, children: [
                if (_offline)
                  const OfflineBanner()
                else if (latest?.source == 'SIMULATED')
                  const SimulatedBanner(),
                const SizedBox(height: Spacing.sm),
                if (latest == null)
                  AppCard(
                    child: Column(children: [
                      const Icon(Icons.sensors_off,
                          size: 52, color: AppColors.muted),
                      const SizedBox(height: 12),
                      Text(tr('Sensor data unavailable'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 6),
                      Text(
                          tr('No ESP32 sensor readings are available right now. Values are not simulated - check the device and pull down to retry.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.muted, height: 1.5)),
                    ]),
                  ),
                if (latest != null) ...[
                  GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: Spacing.sm,
                      crossAxisSpacing: Spacing.sm,
                      childAspectRatio: 1.7,
                      children: [
                        InfoTile(
                            icon: Icons.thermostat,
                            label: tr('Temperature'),
                            value: latest.temperature.toStringAsFixed(1),
                            unit: '°C',
                            color: AppColors.amber),
                        InfoTile(
                            icon: Icons.water_drop_outlined,
                            label: tr('Humidity'),
                            value: latest.humidity.toStringAsFixed(0),
                            unit: '%',
                            color: AppColors.sky),
                        InfoTile(
                            icon: Icons.grass,
                            label: tr('Soil Moisture'),
                            value: latest.soilMoisture.toStringAsFixed(0),
                            unit: '%',
                            color: AppColors.soil),
                        InfoTile(
                            icon: Icons.wb_sunny_outlined,
                            label: tr('Light'),
                            value: latest.light.toStringAsFixed(0),
                            unit: 'lux',
                            color: AppColors.amber),
                      ]),
                  const SizedBox(height: 6),
                  Text(
                      '${tr('Last updated:')} ${latest.timestamp.toString().substring(0, 16)}  ·  ${tr('Device:')} ${latest.deviceId}',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                  SectionHeader(tr('Temperature (recent readings)')),
                  AppCard(
                      child: SensorLineChart(
                          readings: _readings,
                          value: (e) => e.temperature,
                          label: '°C',
                          color: AppColors.amber)),
                  SectionHeader(tr('Humidity (recent readings)')),
                  AppCard(
                      child: SensorLineChart(
                          readings: _readings,
                          value: (e) => e.humidity,
                          label: '%',
                          color: AppColors.sky)),
                  SectionHeader(tr('Soil Moisture (recent readings)')),
                  AppCard(
                      child: SensorLineChart(
                          readings: _readings,
                          value: (e) => e.soilMoisture,
                          label: '%',
                          color: AppColors.soil)),
                ],
                const SizedBox(height: Spacing.sm),
                PrimaryButton(
                    label: tr('DEVICE STATUS'),
                    icon: Icons.settings_outlined,
                    color: AppColors.pine,
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DeviceScreen()))),
                const SizedBox(height: Spacing.xl),
              ]),
            ),
    );
  }
}
