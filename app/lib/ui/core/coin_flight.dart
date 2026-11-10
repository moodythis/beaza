import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Coins flying from a card to where the money went (the Saving tab, or
/// the top of the screen for "tomorrow"), a small pop where they land and a
/// "+amount" badge. Drawn once over everything and removed when done. It
/// only decorates: the move itself is already saved before it starts.
class CoinFlight extends StatefulWidget {
  const CoinFlight._({
    required this.from,
    required this.to,
    required this.label,
    required this.duration,
    required this.onDone,
  });

  /// How long the whole flight takes with motion on.
  static const Duration flightTime = Duration(milliseconds: 800);

  /// How many coins fly.
  static const int coins = 6;

  /// Starts a flight on [overlay]. Does nothing when [duration] is zero
  /// (the phone asks for less motion): callers pass `motion(context, ...)`.
  static void show(
    OverlayState overlay, {
    required Rect from,
    required Offset to,
    required String label,
    required Duration duration,
  }) {
    if (duration <= Duration.zero) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => CoinFlight._(
        from: from,
        to: to,
        label: label,
        duration: duration,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }

  final Rect from;
  final Offset to;
  final String label;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<CoinFlight> createState() => _CoinFlightState();
}

class _CoinFlightState extends State<CoinFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          key: const Key('coinFlight'),
          size: Size.infinite,
          painter: CoinFlightPainter(
            t: _c.value,
            from: widget.from,
            to: widget.to,
            label: widget.label,
            accent: theme.brightness == Brightness.dark
                ? const Color(0xFF3DD68C)
                : const Color(0xFF13804C),
            labelStyle: theme.textTheme.labelLarge!.copyWith(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF062014)
                    : Colors.white,
                fontWeight: FontWeight.w700),
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

/// One frame of the flight at [t] (0 to 1). Public so a picture of it can
/// be made and looked at.
class CoinFlightPainter extends CustomPainter {
  CoinFlightPainter({
    required this.t,
    required this.from,
    required this.to,
    required this.label,
    required this.accent,
    required this.labelStyle,
    required this.textDirection,
  });

  final double t;
  final Rect from;
  final Offset to;
  final String label;
  final Color accent;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  static const Color _gold = Color(0xFFE8B931);
  static const Color _goldRim = Color(0xFFA9790A);

  /// Each coin starts a little after the one before and flies for this
  /// share of the whole time.
  static const double _stagger = 0.06;
  static const double _flight = 0.62;

  /// Where coin [i] is at [t]: on a curve (quadratic Bezier) from its own
  /// spot on the card, up and over, to the target. Null before it leaves
  /// and after it lands.
  static Offset? coinAt(int i, double t, Rect from, Offset to) {
    final p = (t - i * _stagger) / _flight;
    if (p < 0 || p >= 1) return null;
    final e = Curves.easeInOutCubic.transform(p);
    final start = from.center +
        Offset((i - (CoinFlight.coins - 1) / 2) * 16, i.isEven ? -6 : 8);
    final control = Offset(
      (start.dx + to.dx) / 2 + (i.isEven ? 28 : -28),
      math.min(start.dy, to.dy) - 90 - i * 8,
    );
    final a = (1 - e) * (1 - e);
    final b = 2 * (1 - e) * e;
    final c = e * e;
    return Offset(
      a * start.dx + b * control.dx + c * to.dx,
      a * start.dy + b * control.dy + c * to.dy,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The coins: gold and emerald in turn, shrinking as they arrive.
    for (var i = 0; i < CoinFlight.coins; i++) {
      final at = coinAt(i, t, from, to);
      if (at == null) continue;
      final p = ((t - i * _stagger) / _flight).clamp(0.0, 1.0);
      final r = 10 - 4 * p;
      final fill = i.isEven ? _gold : accent;
      final rim = i.isEven ? _goldRim : Colors.white;
      canvas.drawCircle(at, r, Paint()..color = fill);
      canvas.drawCircle(
          at,
          r,
          Paint()
            ..color = rim
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      canvas.drawCircle(
          at,
          r * 0.5,
          Paint()
            ..color = rim.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }

    // The pop where they land.
    if (t >= 0.55) {
      final q = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
      canvas.drawCircle(
          to,
          12 + 22 * q,
          Paint()
            ..color = accent.withValues(alpha: 0.9 * (1 - q))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
      canvas.drawCircle(
          to,
          16 * math.sin(q * math.pi),
          Paint()..color = accent.withValues(alpha: 0.25));
    }

    // The "+amount" badge: floats away from the edge the target is near.
    if (t >= 0.5) {
      final q = ((t - 0.5) / 0.5).clamp(0.0, 1.0);
      final opacity = q < 0.2
          ? q / 0.2
          : q > 0.8
              ? (1 - q) / 0.2
              : 1.0;
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: textDirection,
      )..layout();
      final away = to.dy > size.height / 2 ? -1.0 : 1.0;
      final center = to + Offset(0, away * (34 + 22 * q));
      final w = tp.width + 20;
      final h = tp.height + 10;
      final left = (center.dx - w / 2)
          .clamp(8.0, math.max(8.0, size.width - w - 8))
          .toDouble();
      final rect = Rect.fromLTWH(left, center.dy - h / 2, w, h);
      canvas.saveLayer(
          rect.inflate(2), Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(h / 2)),
          Paint()..color = accent);
      tp.paint(canvas, Offset(rect.left + 10, rect.top + 5));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CoinFlightPainter old) =>
      old.t != t || old.from != from || old.to != to || old.label != label;
}
