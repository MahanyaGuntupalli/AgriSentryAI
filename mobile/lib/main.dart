import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/app_services.dart';
import 'services/translations.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the saved language (EN/HI/TE) before the first frame renders.
  await LanguageService.instance.load();
  // Offline-first core: local DB, connectivity watcher, sync manager.
  // Failures must never block app startup - the app runs fully offline.
  try {
    await AppServices.initialize();
  } catch (_) {/* AppServices stay optional; screens handle absence. */}
  runApp(const AgriSentryApp());
}

class AgriSentryApp extends StatelessWidget {
  const AgriSentryApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
        valueListenable: LanguageService.instance.language,
        builder: (context, lang, _) => MaterialApp(
          onGenerateTitle: (context) => 'AgriSentry AI',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          // Material widgets (dialogs, pickers, text selection menus) follow
          // the selected language instead of always rendering English.
          locale: switch (lang) {
            AppLanguage.hindi => const Locale('hi'),
            AppLanguage.telugu => const Locale('te'),
            AppLanguage.english => const Locale('en'),
          },
          supportedLocales: const [
            Locale('en'),
            Locale('hi'),
            Locale('te'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SplashScreen(),
        ),
      );
}
