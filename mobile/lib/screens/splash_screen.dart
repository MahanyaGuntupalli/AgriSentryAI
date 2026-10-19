import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/translations.dart';
import '../widgets/app_logo.dart';
import 'onboarding_screen.dart';
import 'login_screen.dart';
import 'main_navigation.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..forward();
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2200), _go);
  }

  Future<void> _go() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final onboarded = prefs.getBool('onboarded') ?? false;
    final name = prefs.getString('farmer_name');
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => !onboarded
                ? const OnboardingScreen()
                : (name == null
                    ? const LoginScreen()
                    : const MainNavigationScreen())));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppLanguage>(
        valueListenable: LanguageService.instance.language,
        builder: (context, _, __) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.forest, AppColors.pine])),
          child: Center(
              child: ScaleTransition(
            scale: CurvedAnimation(parent: _c, curve: Curves.easeOutBack),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AppLogo(size: 116, onDark: true),
              const SizedBox(height: 20),
              const Text('AgriSentry AI',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Text(tr('SEE  ·  UNDERSTAND  ·  PREDICT  ·  PREVENT'),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
            ]),
          )),
        ),
      ));
}
