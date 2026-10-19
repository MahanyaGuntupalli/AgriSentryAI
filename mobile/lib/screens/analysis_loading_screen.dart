import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../ai/crop_disease_knowledge.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../services/analysis_orchestrator.dart';
import '../services/api_service.dart';
import '../services/app_services.dart';
import '../services/farm_store.dart';
import '../services/mock_data.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

class AnalysisLoadingScreen extends StatefulWidget {
  final File image;
  final CropType crop;
  const AnalysisLoadingScreen(
      {super.key, required this.image, this.crop = CropType.tomato});
  @override
  State<AnalysisLoadingScreen> createState() => _AnalysisLoadingScreenState();
}

class _AnalysisLoadingScreenState extends State<AnalysisLoadingScreen> {
  static const _messages = [
    'Scanning leaf...',
    'Checking visible symptoms...',
    'Analyzing crop health...',
    'Combining environmental conditions...',
    'Preparing your crop health report...',
  ];
  int _step = 0;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1700),
        (_) {
          if (mounted) {
            setState(() => _step = (_step + 1) % _messages.length);
          }
        });
    _run();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _error = null);

    // Demo pacing for the pure-simulated mode.
    if (AppConfig.dataMode == 'simulated') {
      await Future.delayed(const Duration(seconds: 4));
      return _show(MockData.sampleAnalysis(),
          simulatedFallback: true, image: widget.image);
    }

    // Preferred: the orchestrator (backend -> on-device -> demo), which also
    // persists locally and queues synchronization.
    if (AppServices.isReady) {
      try {
        final outcome = await AppServices.instance.analysis.analyzeImage(
          image: widget.image,
          crop: widget.crop,
        );
        return _show(outcome.result,
            simulatedFallback: outcome.source == AnalysisSource.demo,
            image: widget.image);
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
        return;
      } catch (_) {
        // fall through to the legacy direct-API path
      }
    }

    // Legacy path when services are unavailable (e.g. unusual test envs).
    try {
      final result = await ApiService()
          .analyze(widget.image, crop: widget.crop.id);
      return _show(result, simulatedFallback: false, image: widget.image);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr(
            'The analysis service is unavailable. Check your connection and try again.'));
      }
    }
  }

  void _show(ImageAnalysisResult result,
      {required bool simulatedFallback, required File image}) {
    if (!mounted) return;
    FarmStore.instance.applyScan(result);
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => ResultScreen(
                result: result,
                image: image,
                simulatedFallback: simulatedFallback)));
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppLanguage>(
        valueListenable: LanguageService.instance.language,
        builder: (context, _, __) => PopScope(
        canPop: _error != null, // don't pop mid-analysis
        child: Scaffold(
          body: SafeArea(
              child: Padding(
            padding: Spacing.page,
            child: _error == null
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      width: 190,
                      height: 190,
                      child: Stack(alignment: Alignment.center, children: [
                        const SizedBox(
                            width: 190,
                            height: 190,
                            child: CircularProgressIndicator(
                                strokeWidth: 7,
                                color: AppColors.pine,
                                backgroundColor: AppColors.sage)),
                        ClipOval(
                            child: Image.file(widget.image, cacheWidth: 280,
                                width: 140, height: 140, fit: BoxFit.cover)),
                      ]),
                    ),
                    const SizedBox(height: 36),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: Text(tr(_messages[_step]),
                          key: ValueKey(_step),
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.forest)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                        tr('Our AI is looking at your leaf and your field conditions.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted)),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.photo_camera_front_outlined,
                        size: 64, color: AppColors.amber),
                    const SizedBox(height: 16),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(fontSize: 17, color: AppColors.ink)),
                    const SizedBox(height: 24),
                    PrimaryButton(
                        label: tr('RETAKE PHOTO'),
                        icon: Icons.refresh,
                        onPressed: () => Navigator.pop(context)),
                  ]),
          )),
        ),
      ));
}
