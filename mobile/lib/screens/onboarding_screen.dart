import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/translations.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;
  static const _pages = [
    (Icons.photo_camera, 'See Crop Health',
        'Take a photo of your crop leaf. Our AI checks it for disease in seconds.'),
    (Icons.insights, 'Understand the Risk',
        'Weather, soil and air conditions around your crop give the full picture.'),
    (Icons.trending_up, "Predict What's Next",
        'See if the risk will rise in the coming days - before it happens.'),
    (Icons.checklist, 'Know What To Do',
        'Get simple, clear steps to protect your crop.'),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.instance.language,
      builder: (context, _, __) => Scaffold(
        body: SafeArea(
            child: Column(children: [
          Align(
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const LanguageToggleButton(),
                TextButton(
                    onPressed: _finish,
                    child: Text(tr('Skip'),
                        style: const TextStyle(color: AppColors.muted))),
              ])),
          Expanded(
              child: PageView.builder(
            controller: _pc,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final p = _pages[i];
              return Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child:
                    Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                        color: AppColors.sage.withValues(alpha: 0.35),
                        shape: BoxShape.circle),
                    child: Icon(p.$1, size: 80, color: AppColors.pine),
                  ),
                  const SizedBox(height: 36),
                  Text(tr(p.$2),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.forest)),
                  const SizedBox(height: 14),
                  Text(tr(p.$3),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.muted,
                          height: 1.5)),
                ]),
              );
            },
          )),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  _pages.length,
                  (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.all(4),
                        height: 8,
                        width: i == _page ? 24 : 8,
                        decoration: BoxDecoration(
                            color: i == _page ? AppColors.pine : AppColors.sage,
                            borderRadius: BorderRadius.circular(8)),
                      ))),
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: PrimaryButton(
              label: tr(_page == _pages.length - 1 ? 'Get started' : 'Next'),
              onPressed: () => _page == _pages.length - 1
                  ? _finish()
                  : _pc.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut),
            ),
          ),
        ])),
      ));
}
