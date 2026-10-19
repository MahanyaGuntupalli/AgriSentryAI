import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// AgriSentry AI brand mark (vector - no image assets needed, scales crisply).
///
/// Concept: a healthy leaf (crops) embraced by a shield outline (protection)
/// with a scanning arc (AI analysis) - the whole app's visual identity.
class AppLogo extends StatelessWidget {
  final double size;

  /// Dark backgrounds (splash/header) get the light treatment.
  final bool onDark;

  const AppLogo({super.key, required this.size, this.onDark = false});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _AppLogoPainter(onDark: onDark),
      );
}

class _AppLogoPainter extends CustomPainter {
  final bool onDark;
  _AppLogoPainter({required this.onDark});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);

    // ---- rounded-square gradient tile ----
    final tile = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.24));
    final tilePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.pine, AppColors.forest],
      ).createShader(Rect.fromLTWH(0, 0, s, s));
    canvas.drawRRect(tile, tilePaint);
    // subtle top highlight
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );

    // ---- shield outline (protection) ----
    final shieldPaint = Paint()
      ..color = (onDark ? Colors.white : AppColors.leafLight)
          .withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round;
    final shieldPath = Path()
      ..moveTo(center.dx, s * 0.14)
      ..lineTo(s * 0.78, s * 0.24)
      ..lineTo(s * 0.78, s * 0.52)
      ..quadraticBezierTo(s * 0.78, s * 0.76, center.dx, s * 0.88)
      ..quadraticBezierTo(s * 0.22, s * 0.76, s * 0.22, s * 0.52)
      ..lineTo(s * 0.22, s * 0.24)
      ..close();
    canvas.drawPath(shieldPath, shieldPaint);

    // ---- leaf (crops / health) ----
    final leafPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.leafLight, AppColors.leaf],
      ).createShader(Rect.fromLTWH(s * 0.28, s * 0.28, s * 0.5, s * 0.5));
    // Leaf: two symmetric bezier lobes meeting at tip and stem.
    final leafPath = Path()
      ..moveTo(s * 0.34, s * 0.70)
      ..quadraticBezierTo(s * 0.22, s * 0.50, s * 0.42, s * 0.32)
      ..quadraticBezierTo(s * 0.62, s * 0.16, s * 0.72, s * 0.34)
      ..quadraticBezierTo(s * 0.82, s * 0.54, s * 0.60, s * 0.72)
      ..quadraticBezierTo(s * 0.47, s * 0.81, s * 0.34, s * 0.70)
      ..close();
    canvas.drawPath(leafPath, leafPaint);

    // Leaf midrib
    final veinPaint = Paint()
      ..color = AppColors.forest.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.030
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.37, s * 0.68)
        ..quadraticBezierTo(s * 0.50, s * 0.54, s * 0.66, s * 0.38),
      veinPaint,
    );

    // ---- AI scan arc ----
    final scanPaint = Paint()
      ..color = AppColors.sky
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: s * 0.40),
      -math.pi * 0.78,
      math.pi * 0.56,
      false,
      scanPaint,
    );
    // scan dot at the arc head
    const angle = -math.pi * 0.78 + math.pi * 0.56;
    canvas.drawCircle(
      Offset(center.dx + s * 0.40 * math.cos(angle),
          center.dy + s * 0.40 * math.sin(angle)),
      s * 0.040,
      Paint()..color = AppColors.sky,
    );
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter old) => old.onDark != onDark;
}
