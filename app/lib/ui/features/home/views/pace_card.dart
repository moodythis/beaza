import 'dart:math' as math;

import 'package:beaza/domain/use_cases/day_pace.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/views/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// "Today's pace": today's spending drawn over the person's usual day, with
/// the rest of a usual day projected from now, the limit as a line and the
/// late-night hours shaded. It says before the limit is crossed whether a
/// usual evening would cross it, and when.
class PaceCard extends StatelessWidget {
  const PaceCard({super.key, required this.pace});

  final DayPace pace;

  static Color good(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF3DD68C) : const Color(0xFF13804C);
  static Color warn(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFF5B84B) : const Color(0xFF8A5A00);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    String money(int f) => l10n.bhd(formatFils(f));
    String clock(int minute) => DateFormat.jm(locale)
        .format(DateTime.utc(2026, 1, 1, minute ~/ 60, minute % 60));
    String hour(int h) =>
        DateFormat.j(locale).format(DateTime.utc(2026, 1, 1, h));
    final b = theme.brightness;
    final (Color tone, String line) = switch (pace.status) {
      PaceStatus.onTrack => (
          good(b),
          l10n.paceOnTrack(money(pace.stillUsualFils), money(pace.leftFils))
        ),
      PaceStatus.tight => (
          warn(b),
          l10n.paceTight(money(pace.stillUsualFils), money(pace.leftFils))
        ),
      PaceStatus.willPass => (
          theme.colorScheme.error,
          pace.passMinute == null
              ? l10n.paceWillPass(money(pace.stillUsualFils), money(pace.overByFils))
              : l10n.paceWillPassAt(money(pace.stillUsualFils),
                  money(pace.overByFils), clock(pace.passMinute!))
        ),
      PaceStatus.passed => (
          theme.colorScheme.error,
          l10n.pacePassed(money(pace.stillUsualFils))
        ),
    };
    final late = pace.lateFils;
    final showLate = late > 0 &&
        pace.status != PaceStatus.onTrack &&
        late * 2 >= pace.stillUsualFils;
    return Card(
      key: const Key('paceCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.timeline, color: tone),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(l10n.paceTitle, style: theme.textTheme.titleMedium)),
              Text(l10n.paceBasis(pace.historyDays),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 10),
            Semantics(
              label: line,
              excludeSemantics: true,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: motion(context, const Duration(milliseconds: 700)),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => SizedBox(
                  height: 132,
                  child: CustomPaint(
                    key: const Key('paceChart'),
                    painter: PacePainter(
                      pace,
                      progress: t,
                      today: theme.colorScheme.primary,
                      ahead: tone,
                      usual: theme.colorScheme.outline,
                      limit: theme.colorScheme.error,
                      late: theme.colorScheme.primary.withValues(alpha: 0.08),
                      grid: theme.colorScheme.outlineVariant,
                      labels: [hour(6), hour(12), hour(18)],
                      labelStyle: theme.textTheme.labelSmall!.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textDirection: Directionality.of(context),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 4, children: [
              _Key(color: theme.colorScheme.primary, label: l10n.paceToday),
              _Key(color: tone, label: l10n.paceAhead, dotted: true),
              _Key(color: theme.colorScheme.outline, label: l10n.paceUsual, dashed: true),
              _Key(
                  color: theme.colorScheme.error,
                  label: l10n.paceLimit(money(pace.limitFils)),
                  dashed: true),
            ]),
            const SizedBox(height: 10),
            Text(line,
                key: const Key('paceLine'),
                style: theme.textTheme.bodyMedium?.copyWith(color: tone)),
            if (showLate) ...[
              const SizedBox(height: 4),
              Text(l10n.paceLate(money(late)),
                  key: const Key('paceLate'), style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.color,
    required this.label,
    this.dashed = false,
    this.dotted = false,
  });

  final Color color;
  final String label;
  final bool dashed;
  final bool dotted;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 8,
            child: CustomPaint(painter: _KeyPainter(color, dashed, dotted)),
          ),
          const SizedBox(width: 6),
          // Wraps on a narrow phone with large text instead of overflowing.
          Flexible(
              child: Text(label, style: Theme.of(context).textTheme.labelSmall)),
        ],
      );
}

class _KeyPainter extends CustomPainter {
  _KeyPainter(this.color, this.dashed, this.dotted);
  final Color color;
  final bool dashed;
  final bool dotted;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (dotted) {
      for (var x = 1.5; x < size.width; x += 4.5) {
        canvas.drawCircle(Offset(x, y), 1.4, Paint()..color = color);
      }
      return;
    }
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      return;
    }
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(_KeyPainter old) => old.color != color;
}

/// The pace chart. Time runs from midnight to midnight along the reading
/// direction (right to left in Arabic); height is fils from 0 to a little
/// above the largest of the limit, the expected end and a usual day.
class PacePainter extends CustomPainter {
  PacePainter(
    this.pace, {
    required this.progress,
    required this.today,
    required this.ahead,
    required this.usual,
    required this.limit,
    required this.late,
    required this.grid,
    required this.labels,
    required this.labelStyle,
    required this.textDirection,
  });

  final DayPace pace;
  final double progress;
  final Color today;

  /// The rest of a usual day from now, in the status colour.
  final Color ahead;
  final Color usual;
  final Color limit;
  final Color late;
  final Color grid;
  final List<String> labels;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  static const double _axis = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height - _axis;
    final rtl = textDirection == TextDirection.rtl;
    final top = [pace.limitFils, pace.expectedFils, pace.usualDayFils, 1]
            .reduce(math.max) *
        1.12;
    double x(int minute) {
      final f = minute / kDayMinutes * w;
      return rtl ? w - f : f;
    }

    double y(int fils) => h - (fils / top) * h;

    // Late night: 22:00 to midnight, and midnight to 03:00.
    final band = Paint()..color = late;
    canvas.drawRect(Rect.fromLTRB(math.min(x(kLateNightStart), x(kDayMinutes)), 0,
        math.max(x(kLateNightStart), x(kDayMinutes)), h), band);
    canvas.drawRect(
        Rect.fromLTRB(math.min(x(0), x(180)), 0, math.max(x(0), x(180)), h), band);

    // Hour grid and labels.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h), Offset(w, h), gridPaint);
    // Ticks at midnight, 06, 12, 18 and midnight; labels at 06, 12 and 18.
    for (final m in [0, 360, 720, 1080, kDayMinutes]) {
      canvas.drawLine(Offset(x(m), h), Offset(x(m), h + 3), gridPaint);
    }
    for (var i = 0; i < labels.length; i++) {
      final m = (i + 1) * 6 * 60;
      final gx = x(m);
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: textDirection,
      )..layout();
      final lx = (gx - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(lx, h + 4));
    }

    // The limit.
    final ly = y(pace.limitFils);
    final limitPaint = Paint()
      ..color = limit
      ..strokeWidth = 1.5;
    for (var d = 0.0; d < w; d += 8) {
      canvas.drawLine(Offset(d, ly), Offset(math.min(d + 4, w), ly), limitPaint);
    }

    // A usual day, dashed.
    final usualPaint = Paint()
      ..color = usual
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    Offset? prev;
    for (var m = 0; m <= kDayMinutes; m += 20) {
      final p = Offset(x(m), y(pace.usualDayFils * pace.shareAt(m) ~/ 1000));
      if (prev != null && (m ~/ 20).isEven) canvas.drawLine(prev, p, usualPaint);
      prev = p;
    }

    // Today so far, drawn in as [progress] goes from 0 to 1.
    final todayPaint = Paint()
      ..color = today
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final until = (pace.nowMinute * progress).round();
    final path = Path()..moveTo(x(0), y(0));
    final byHour = pace.todayByHour;
    for (var hr = 1; hr < byHour.length; hr++) {
      final m = math.min(hr * 60, pace.nowMinute);
      if (m > until) break;
      path.lineTo(x(m), y(byHour[hr - 1]));
      path.lineTo(x(m), y(byHour[hr]));
    }
    if (until < pace.nowMinute) {
      path.lineTo(x(until), y(byHour[until ~/ 60]));
    }
    canvas.drawPath(path, todayPaint);

    if (progress < 1) return;
    // The rest of a usual day from now, dotted.
    final rest = Paint()
      ..color = ahead
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var m = pace.nowMinute; m < kDayMinutes; m += 12) {
      final p = Offset(x(m), y(pace.projectedAt(m)));
      canvas.drawCircle(p, 1.4, rest);
    }
    final end = Offset(x(kDayMinutes), y(pace.expectedFils));
    canvas.drawCircle(end, 3, rest);
    // Where a usual rest of the day crosses the limit.
    final pass = pace.passMinute;
    if (pass != null) {
      final at = Offset(x(pass), ly);
      canvas.drawLine(Offset(at.dx, ly - 7), Offset(at.dx, ly + 7),
          Paint()
            ..color = ahead
            ..strokeWidth = 2);
      canvas.drawCircle(at, 4, Paint()..color = ahead);
    }
    // Now.
    final now = Offset(x(pace.nowMinute), y(pace.spentFils));
    canvas.drawCircle(now, 5.5, Paint()..color = today);
    canvas.drawCircle(
        now,
        5.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(PacePainter old) =>
      old.progress != progress ||
      old.pace != pace ||
      old.today != today ||
      old.ahead != ahead;
}
