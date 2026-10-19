import 'package:flutter/material.dart';

import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Privacy Policy and Terms of Service.
///
/// Content rules: every statement below describes behavior that actually
/// exists in this codebase (local database on the device, optional backend
/// upload of scan images, OpenWeatherMap weather lookups, no advertising or
/// analytics SDKs). Nothing is claimed that the app does not do.
///
/// The body text is intentionally provided in English only, with a localized
/// notice saying so, because precise legal wording in Hindi/Telugu is not
/// maintained by this project. Titles and navigation are fully localized.

class LegalNoticeHeader extends StatelessWidget {
  const LegalNoticeHeader({super.key});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(Spacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.translate, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr('This document is provided in English.'),
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.muted, height: 1.4)),
          ),
        ]),
      );
}

class _LegalSection extends StatelessWidget {
  final String title;
  final String body;
  const _LegalSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(title),
              style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.forest)),
          const SizedBox(height: 4),
          Text(body,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.ink, height: 1.5)),
        ]),
      );
}

class _LegalScaffold extends StatelessWidget {
  final String title;
  final List<Widget> sections;
  const _LegalScaffold({required this.title, required this.sections});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
        valueListenable: LanguageService.instance.language,
        builder: (context, _, __) => Scaffold(
          appBar: AppBar(title: Text(tr(title))),
          body: ListView(
            padding: Spacing.page,
            children: [
              const SizedBox(height: Spacing.sm),
              const LegalNoticeHeader(),
              const SizedBox(height: Spacing.md),
              ...sections,
              const SizedBox(height: Spacing.lg),
            ],
          ),
        ),
      );
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => const _LegalScaffold(
        title: 'Privacy Policy',
        sections: [
          _LegalSection(
            title: 'What this app stores on your device',
            body:
                'AgriSentry AI keeps your selected crop, scan history, sensor '
                'readings it has received, and cached weather on the device '
                'itself, in a local database. This data stays on the device '
                'and is used to show your farm history and to keep the app '
                'working when the internet is unavailable.',
          ),
          _LegalSection(
            title: 'What is sent to the backend',
            body:
                'When you run a scan and a backend server is configured and '
                'reachable, the app uploads the photo you captured together '
                'with the crop you selected, so the server can analyse the '
                'image for disease. Scan results and the image are stored in '
                'the server database to build your scan history. If no '
                'backend is configured, the app does not upload anything and '
                'says so on screen.',
          ),
          _LegalSection(
            title: 'Location and weather',
            body:
                'The backend requests current weather from OpenWeatherMap '
                'using field coordinates configured by the server operator. '
                'The app itself does not read your GPS position. If the '
                'weather provider is unreachable, the app shows "weather '
                'unavailable" instead of estimated values.',
          ),
          _LegalSection(
            title: 'What we do not do',
            body:
                'The app contains no advertising, no analytics or tracking '
                'SDKs, and does not sell or share your data with third '
                'parties. Images are used only to produce your analysis '
                'result.',
          ),
          _LegalSection(
            title: 'Deleting your data',
            body:
                'Clearing the app storage on your device removes all locally '
                'stored history. Data held in the backend database is under '
                'the control of whoever operates that server for your '
                'organisation, and deletion requests should be raised with '
                'that operator.',
          ),
        ],
      );
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _LegalScaffold(
        title: 'Terms and Conditions',
        sections: [
          _LegalSection(
            title: 'Purpose of this app',
            body:
                'AgriSentry AI is a decision-support tool for farmers. It '
                'analyses crop leaf photos, reports model confidence, and '
                'combines them with weather and sensor readings where those '
                'are genuinely available.',
          ),
          _LegalSection(
            title: 'Not professional advice',
            body:
                'Results are estimates from statistical models and labelled '
                'rule engines. They can be wrong. Always confirm with your '
                'local agricultural officer before buying or applying any '
                'treatment. The app does not replace professional '
                'agricultural advice.',
          ),
          _LegalSection(
            title: 'Honest limitations',
            body:
                'The app states plainly when it cannot help: it shows '
                '"identification unavailable" when a model is not deployed, '
                '"no reliable disease detected" when confidence is below '
                'threshold, and "unavailable" for weather or sensors it '
                'cannot reach. It never fills those gaps with simulated '
                'values presented as real.',
          ),
          _LegalSection(
            title: 'Acceptable use',
            body:
                'Use the app only for crops you are authorised to photograph '
                'and analyse. Do not attempt to disrupt the backend service '
                'or upload content unrelated to crop analysis.',
          ),
          _LegalSection(
            title: 'Availability and liability',
            body:
                'The service depends on your network, the backend server, '
                'and external providers such as the weather service, and may '
                'be unavailable at times. To the extent permitted by law, '
                'the operators of this service are not liable for crop '
                'losses or decisions made on the basis of app results.',
          ),
        ],
      );
}
