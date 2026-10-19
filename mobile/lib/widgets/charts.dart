import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../utils/crop_intelligence.dart';

class HealthRing extends StatelessWidget {
  final int percent;
  final String label;
  const HealthRing({super.key, required this.percent, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = percent >= 70
        ? AppColors.pine
        : percent >= 40
            ? AppColors.amber
            : AppColors.danger;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent / 100),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 132,
        height: 132,
        child: CustomPaint(
          painter: _RingPainter(v, color),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${(v * 100).round()}%',
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900, color: color)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                      height: 1.2)),
            ]),
          ),
        ),
      ),
    );
  }
}

class RiskGauge extends StatelessWidget {
  final int score;
  final String level;
  const RiskGauge({super.key, required this.score, required this.level});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.riskColor(level);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 168,
        height: 168,
        child: CustomPaint(
          painter: _RingPainter(v, color, stroke: 14),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${(v * 100).round()}',
                  style: TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w900, color: color)),
              Text(trLevel(level),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: 0.6)),
              Text(tr('ESTIMATED RISK'),
                  style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  final double stroke;
  _RingPainter(this.v, this.color, {this.stroke = 12});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = min(size.width, size.height) / 2 - 10;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        0,
        2 * pi,
        false,
        Paint()
          ..color = AppColors.sage.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -pi / 2,
        2 * pi * v,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.v != v || old.color != color;
}

class ConfidenceBar extends StatelessWidget {
  final int percent;
  const ConfidenceBar(this.percent, {super.key});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: percent / 100),
        duration: const Duration(milliseconds: 900),
        builder: (context, v, _) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 10,
            backgroundColor: AppColors.sage.withValues(alpha: 0.5),
            valueColor: const AlwaysStoppedAnimation(AppColors.pine),
          ),
        ),
      );
}

class RiskTimeline extends StatelessWidget {
  final List<FutureRiskPoint> points;
  const RiskTimeline(this.points, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        children: points.asMap().entries.map((e) {
          final p = e.value;
          final last = e.key == points.length - 1;
          final c = AppColors.riskColor(p.level);
          return Expanded(
            child: Row(children: [
              Expanded(
                  child: Column(children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.withValues(alpha: 0.45))),
                  child: Column(children: [
                    Text('${p.score}',
                        style: TextStyle(
                            color: c,
                            fontWeight: FontWeight.w900,
                            fontSize: 16)),
                    Text(trLevel(p.level),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: c,
                            fontWeight: FontWeight.w800,
                            fontSize: 10)),
                  ]),
                ),
                const SizedBox(height: 6),
                Text(p.horizon == 'CURRENT' ? tr('NOW') : tr(p.horizon),
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w800)),
              ])),
              if (!last)
                Icon(Icons.arrow_forward,
                    size: 14, color: c.withValues(alpha: 0.55)),
            ]),
          );
        }).toList(),
      );
}

class FutureRiskChart extends StatelessWidget {
  final List<FutureRiskPoint> points;
  const FutureRiskChart(this.points, {super.key});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Text(tr('Not enough readings yet for a chart.'),
          style: const TextStyle(color: AppColors.muted));
    }
    final spots = points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.score.toDouble()))
        .toList();
    return SizedBox(
      height: 180,
      child: LineChart(LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.line.withValues(alpha: 0.8), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 25,
              getTitlesWidget: (v, _) => Text('${v.toInt()}',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                final h = points[i].horizon;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(h == 'CURRENT' ? tr('NOW') : tr(h),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.pine,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                radius: 4,
                color: AppColors.riskColor(
                    points[s.x.toInt().clamp(0, points.length - 1)].level),
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.pine.withValues(alpha: 0.22),
                  AppColors.pine.withValues(alpha: 0.02),
                ],
              ),
            ),
          )
        ],
      )),
    );
  }
}

class SensorLineChart extends StatefulWidget {
  final List<EnvironmentalData> readings;
  final double Function(EnvironmentalData) value;
  final String label;
  final Color color;
  const SensorLineChart(
      {super.key,
      required this.readings,
      required this.value,
      required this.label,
      this.color = AppColors.pine});

  @override
  State<SensorLineChart> createState() => _SensorLineChartState();
}

class _SensorLineChartState extends State<SensorLineChart> {
  late List<FlSpot> _spots;

  @override
  void initState() {
    super.initState();
    _rebuildSpots();
  }

  @override
  void didUpdateWidget(covariant SensorLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.readings, widget.readings)) {
      _rebuildSpots();
    }
  }

  void _rebuildSpots() {
    _spots = widget.readings
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), widget.value(e.value)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readings.length < 2) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(tr('Not enough readings yet for a chart.'),
            style: const TextStyle(color: AppColors.muted)),
      );
    }
    return RepaintBoundary(
      child: SizedBox(
        height: 150,
        child: LineChart(LineChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: _spots,
              isCurved: true,
              color: widget.color,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                  show: true, color: widget.color.withValues(alpha: 0.12)),
            )
          ],
        )),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final IconData icon;
  final String label, value, unit;
  final Color color;
  final String? status;
  final String? hint;
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.status,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor =
        status == null ? AppColors.muted : AppColors.riskColor(status!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Spacing.radius),
        boxShadow: AppShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          if (status != null)
            Text(trLevel(status!),
                style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4)),
        ]),
        const SizedBox(height: 10),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink)),
            TextSpan(
                text: ' $unit',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ])),
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(tr(hint!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.muted, height: 1.3)),
        ],
      ]),
    );
  }
}

class MultimodalStrip extends StatelessWidget {
  final bool hasImage;
  final bool hasSensors;
  final bool hasWeather;
  final bool hasHistory;
  const MultimodalStrip({
    super.key,
    this.hasImage = true,
    this.hasSensors = false,
    this.hasWeather = false,
    this.hasHistory = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget node(IconData icon, String label, bool on) => Expanded(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: on
                    ? AppColors.pine.withValues(alpha: 0.12)
                    : AppColors.sage.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon,
                  color: on ? AppColors.pine : AppColors.muted, size: 20),
            ),
            const SizedBox(height: 6),
            Text(tr(label),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: on ? AppColors.forest : AppColors.muted)),
          ]),
        );
    return Column(children: [
      Row(children: [
        node(Icons.eco, 'Leaf', hasImage),
        node(Icons.sensors, 'Sensors', hasSensors),
        node(Icons.cloud_outlined, 'Weather', hasWeather),
        node(Icons.spa_outlined, 'Crop', true),
        node(Icons.history, 'History', hasHistory),
      ]),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.forest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.auto_awesome, color: AppColors.leafLight, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(tr('AgriSentry combines all of this before recommending action.'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        ]),
      ),
    ]);
  }
}

class SourceChip extends StatelessWidget {
  final String source;
  const SourceChip(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
    final live = isLiveSource(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (live ? AppColors.pine : AppColors.amber).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Spacing.badge),
      ),
      child: Text(live ? tr('LIVE DATA') : tr('CACHED / SIMULATED'),
          style: TextStyle(
              color: live ? AppColors.pine : const Color(0xFF9A6B1A),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4)),
    );
  }
}

class ConnectionPill extends StatelessWidget {
  final bool connected;
  final bool simulated;
  final String? updated;
  const ConnectionPill(
      {super.key,
      required this.connected,
      this.simulated = false,
      this.updated});

  @override
  Widget build(BuildContext context) {
    final label = !connected
        ? tr('OFFLINE')
        : simulated
            ? tr('SIMULATED')
            : tr('CONNECTED');
    final color = !connected
        ? AppColors.danger
        : simulated
            ? AppColors.amber
            : AppColors.pine;
    return Semantics(
      label: '$label ${updated ?? ''}',
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        if (updated != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(updated!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
        ],
      ]),
    );
  }
}

class QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const QuickAction(
      {super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppShadows.card,
          ),
          child: Column(children: [
            Icon(icon, color: AppColors.pine),
            const SizedBox(height: 6),
            Text(tr(label),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.forest)),
          ]),
        ),
      );
}
