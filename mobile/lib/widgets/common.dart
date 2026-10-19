/// Reusable design-system widgets (Module 11 section 28).
library;
import 'package:flutter/material.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child,
      this.padding = const EdgeInsets.all(Spacing.md), this.color, this.onTap});
  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(Spacing.radius),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
        borderRadius: BorderRadius.circular(Spacing.radius),
        onTap: onTap,
        child: card);
  }
}

/// Top-of-home branding header.
///
/// Layout contract (responsive audit):
/// - Row 1: logo + greeting + app title + crop line. The title is wrapped in a
///   [FittedBox] with softWrap disabled so "AgriSentry AI" can NEVER break
///   mid-word ("AGRISENTR / Y") on narrow screens - it scales down instead.
/// - Row 2: a dedicated action row (speaker, language, alerts) kept OFF the
///   title line so the title always owns its full available width.
class PremiumFarmHeader extends StatelessWidget {
    final String greeting;
    final String farmer;
    final int alertCount;
    final VoidCallback onAlerts;
    final String Function() spokenSummary;

    /// Dynamic crop line under the app name, e.g. 'Your Tomato Field' or
    /// the neutral 'Your Crop - scan or select one to begin'.
    final String cropLine;

    const PremiumFarmHeader({
      super.key,
      required this.greeting,
      required this.farmer,
      required this.alertCount,
      required this.onAlerts,
      required this.spokenSummary,
      this.cropLine = 'Your Crop',
    });

    @override
    Widget build(BuildContext context) => Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 10, 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.forest, AppColors.pine],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(Spacing.radius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2612382A),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Row 1: identity ---
              Row(
                children: [
                  const AppLogo(size: 46, onDark: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting, $farmer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // FittedBox + no soft-wrap: the brand name scales to
                        // fit instead of ever breaking mid-word.
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'AgriSentry AI',
                            softWrap: false,
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        Text(
                          cropLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.leafLight,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // --- Row 2: controls, off the title line ---
              const SizedBox(height: 8),
              IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: Row(
                  children: [
                    SpeakButton(text: spokenSummary),
                    const LanguageToggleButton(),
                    const Spacer(),
                    IconButton(
                      tooltip: tr('Alerts'),
                      onPressed: onAlerts,
                      icon: Badge(
                        isLabelVisible: alertCount > 0,
                        label: Text('$alertCount'),
                        child: const Icon(Icons.notifications_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
  }

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  const PrimaryButton({super.key, required this.label, this.icon,
      required this.onPressed, this.color});
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.arrow_forward),
        label: Text(label),
        style: ElevatedButton.styleFrom(backgroundColor: color ?? AppColors.forest),
      );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, Spacing.lg, 2, Spacing.sm),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.forest)),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(actionLabel!,
                  style: const TextStyle(
                      color: AppColors.pine,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
        ]),
      );
}

/// Risk badge with a smooth color transition whenever [level] changes
/// (e.g. a scan refresh moves risk from LOW to HIGH) instead of an abrupt
/// color flip.
class RiskBadge extends StatelessWidget {
  final String level;
  const RiskBadge(this.level, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.riskColor(level);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: c),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: color!.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Spacing.badge),
              border: Border.all(color: color.withValues(alpha: 0.5))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 9, color: color),
            const SizedBox(width: 6),
            Text(trLevel(level),
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5)),
          ]),
        );
      },
    );
  }
}

/// Fades + slides a child in once, on first build. Purely additive visual
/// polish - wraps existing widgets without changing their layout or logic.
/// [delay] lets a list of these be staggered for a premium "cascading" feel.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

class InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value, unit;
  final Color? color;
  const InfoTile({super.key, required this.icon, required this.label,
      required this.value, required this.unit, this.color});
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(Spacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color ?? AppColors.pine, size: 20),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: value,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink)),
            TextSpan(
                text: ' $unit',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ])),
        ]),
      );
}

class SimulatedBanner extends StatelessWidget {
  final String message;
  const SimulatedBanner(
      [this.message = 'SIMULATED DATA - development data, not live sensors',
      Key? key])
      : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
        color: AppColors.amber.withValues(alpha: 0.15),
        child: Row(children: [
          const Icon(Icons.science_outlined, size: 15, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
              child: Text(tr(message),
                  style: const TextStyle(
                      color: Color(0xFF9A6B1A),
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
        ]),
      );
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
        color: AppColors.danger.withValues(alpha: 0.1),
        child: Row(children: [
          const Icon(Icons.cloud_off, size: 15, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
              child: Text(tr('OFFLINE - showing saved simulated data'),
                  style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
        ]),
      );
}

/// Explicit EN/HI/TE language selector for every screen that uses it.
/// when the language changes and notifies [onChange] so the screen can stop
/// any ongoing speech in the language that is no longer selected.
class LanguageToggleButton extends StatelessWidget {
  final VoidCallback? onChange;
  const LanguageToggleButton({super.key, this.onChange});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
        valueListenable: LanguageService.instance.language,
       builder: (context, lang, _) => PopupMenuButton<AppLanguage>(
         tooltip: tr('Select language'),
         onSelected: (selected) async {
           await Speaker.instance.stop();
           await LanguageService.instance.set(selected);
           onChange?.call();
         },
         itemBuilder: (_) => const [
           PopupMenuItem(value: AppLanguage.english, child: Text('English')),
           PopupMenuItem(value: AppLanguage.hindi, child: Text('हिन्दी')),
           PopupMenuItem(value: AppLanguage.telugu, child: Text('తెలుగు')),
         ],
         child: Padding(
           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
           child: Row(mainAxisSize: MainAxisSize.min, children: [
             const Icon(Icons.translate, size: 18, color: AppColors.pine),
             const SizedBox(width: 5),
             Text(switch (lang) {
               AppLanguage.english => 'English',
               AppLanguage.hindi => 'हिन्दी',
               AppLanguage.telugu => 'తెలుగు',
             },
                 style: const TextStyle(
                     color: AppColors.pine, fontWeight: FontWeight.w800)),
             const Icon(Icons.arrow_drop_down, color: AppColors.pine),
           ]),
         ),
       ),
      );
}

/// Speaker button that reads the current screen aloud (EN or TE). Stops any
/// ongoing speech when tapped while already speaking.
class SpeakButton extends StatelessWidget {
  final String Function() text;
  const SpeakButton({super.key, required this.text});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: Speaker.instance.speaking,
        builder: (context, speaking, _) => IconButton(
          tooltip: tr(speaking ? 'Stop' : 'Read aloud'),
          onPressed: () =>
              speaking ? Speaker.instance.stop() : Speaker.instance.speak(text()),
          icon: Icon(speaking ? Icons.stop_circle_outlined : Icons.volume_up),
        ),
      );
}

class LoadingView extends StatelessWidget {
  final String message;
  const LoadingView([this.message = 'Loading...', Key? key]) : super(key: key);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: AppColors.pine),
            const SizedBox(height: 16),
            Text(tr(message),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted)),
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyView({super.key, required this.title, required this.message,
      this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.eco_outlined, size: 56, color: AppColors.leaf),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.forest)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted)),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              PrimaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(tr('Check that the backend is running and try again.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              PrimaryButton(
                  label: tr('Try again'), icon: Icons.refresh, onPressed: onRetry),
            ],
          ]),
        ),
      );
}