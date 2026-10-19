import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_services.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  WeatherData? _w;
  bool _offline = true;

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

  String _spokenWeather() {
    final weather = _w;
    if (weather == null) return tr('Weather data unavailable');
    return '${tr('Weather')}: ${weather.temperature ?? 0} degrees. '
        '${tr(weather.condition ?? '')}. ${tr('Humidity')}: '
        '${weather.humidity ?? 0} percent. '
        '${tr('Rainfall')}: ${weather.rainfall ?? 0} millimeters.';
  }

  Future<void> _load() async {
    try {
      if (AppConfig.dataMode == 'simulated') throw Exception('simulated mode');
      final w = await ApiService().currentWeather();
      // Cache for offline use (Master Prompt section 5).
      if (AppServices.isReady) {
        await AppServices.instance.db.saveWeather({
          'temperature': w.temperature,
          'humidity': w.humidity,
          'rainfall': w.rainfall,
          'condition': w.condition,
          'forecast_trend': w.forecastTrend,
          'timestamp': w.timestamp.toIso8601String(),
          'source': w.source,
        });
      }
      setState(() {
        _w = w;
        _offline = false;
      });
    } catch (_) {
      // Offline: ONLY the last cached REAL weather. Data-integrity rule:
      // simulated/demo weather is never substituted silently - when nothing
      // real is available the screen says so explicitly.
      WeatherData? cached;
      if (AppServices.isReady) {
        final raw = await AppServices.instance.db.cachedWeather();
        if (raw != null) cached = WeatherData.fromJson(raw);
      }
      setState(() {
        _w = cached;
        _offline = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    if (w == null) {
      // Explicit unavailable state (audit section 10) - no fabricated values.
      return Scaffold(
        appBar: AppBar(
            title: Text(tr('Weather')),
            actions: [
              SpeakButton(text: _spokenWeather),
              const LanguageToggleButton(),
            ]),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: Spacing.page, children: [
            const OfflineBanner(),
            const SizedBox(height: Spacing.lg),
            AppCard(
              child: Column(children: [
                const Icon(Icons.cloud_off,
                    size: 56, color: AppColors.muted),
                const SizedBox(height: 12),
                Text(tr('Weather data unavailable'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 6),
                Text(
                    tr('No live weather is available right now. Values are not simulated - pull down to retry.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.muted, height: 1.5)),
              ]),
            ),
            const SizedBox(height: Spacing.md),
            PrimaryButton(
                label: tr('Retry'),
                icon: Icons.refresh,
                onPressed: _load),
            const SizedBox(height: Spacing.xl),
          ]),
        ),
      );
    }
    final rainy = w.forecastTrend == 'WORSENING';
    return Scaffold(
      appBar: AppBar(
          title: Text(tr('Weather')),
          actions: [
            SpeakButton(text: _spokenWeather),
            const LanguageToggleButton(),
          ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: Spacing.page, children: [
          if (_offline)
            const OfflineBanner()
          else if (w.source == 'SIMULATED')
            const SimulatedBanner(),
          const SizedBox(height: Spacing.sm),
          AppCard(
            color: AppColors.sky.withValues(alpha: 0.08),
            child: Column(children: [
              Icon(rainy ? Icons.water_drop : Icons.wb_sunny,
                  size: 56, color: AppColors.sky),
              const SizedBox(height: 8),
              Text('${w.temperature?.toStringAsFixed(0) ?? '--'}°C',
                  style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      color: AppColors.forest)),
              Text(tr(w.condition ?? ''),
                  style: const TextStyle(fontSize: 17, color: AppColors.muted)),
              const SizedBox(height: 4),
              Text('${tr('Source:')}: ${w.source}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ),
          SectionHeader(tr('Right Now')),
          GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: Spacing.sm,
              crossAxisSpacing: Spacing.sm,
              childAspectRatio: 1.7,
              children: [
                InfoTile(
                    icon: Icons.water_drop_outlined,
                    label: tr('Humidity'),
                    value: w.humidity?.toStringAsFixed(0) ?? '--',
                    unit: '%',
                    color: AppColors.sky),
                InfoTile(
                    icon: Icons.umbrella_outlined,
                    label: tr('Rainfall'),
                    value: w.rainfall?.toStringAsFixed(1) ?? '--',
                    unit: 'mm',
                    color: AppColors.sky),
              ]),
          const SizedBox(height: Spacing.sm),
          SectionHeader(tr('Agricultural Impact')),
          if (rainy)
            AppCard(
              color: AppColors.amber.withValues(alpha: 0.12),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.amber),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(tr('Farm warning'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF9A6B1A))),
                          const SizedBox(height: 4),
                          Text(
                              tr('Rain expected soon. Increased humidity may increase disease risk. Check that leaves can dry quickly and consider scanning a leaf after the rain.'),
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.ink,
                                  height: 1.5)),
                        ])),
                  ]),
            )
          else if ((w.humidity ?? 0) >= 80)
            AppCard(
              color: AppColors.amber.withValues(alpha: 0.12),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.water_drop, color: AppColors.sky),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(tr('Humidity is high'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.forest)),
                          const SizedBox(height: 4),
                          Text(
                              tr('High humidity may increase fungal disease risk. Watch leaf condition and scan a leaf if spots appear.'),
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.ink,
                                  height: 1.5)),
                        ])),
                  ]),
            )
          else
            AppCard(
                child: Row(children: [
              const Icon(Icons.check_circle_outline, color: AppColors.pine),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      tr('Weather outlook is stable or improving. Keep up normal monitoring.'),
                      style: const TextStyle(fontSize: 13.5))),
            ])),
          const SizedBox(height: Spacing.sm),
          Text(
            tr('Weather feeds directly into the AgriSentry AI risk engine - '
                'a scan taken now combines these conditions with the leaf image.'),
            style: const TextStyle(
                fontSize: 12, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: Spacing.xl),
        ]),
      ),
    );
  }
}
