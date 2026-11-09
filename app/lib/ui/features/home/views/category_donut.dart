import 'dart:math' as math;

import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/views/home_shell.dart';
import 'package:flutter/material.dart';

/// One colour per category, told apart by lightness as well as hue.
Color categoryColor(String bucket) => switch (bucket) {
      'food' => const Color(0xFF1E9E63),
      'shopping' => const Color(0xFF3B7DD8),
      'transport' => const Color(0xFFE08A1E),
      'bills' => const Color(0xFF8E5CC8),
      'groceries' => const Color(0xFF7FCFC4),
      'entertainment' => const Color(0xFFD6457A),
      'health' => const Color(0xFFB8322A),
      'education' => const Color(0xFFF2C94C),
      'other' => const Color(0xFF6E7B88),
      kTransferBucket => const Color(0xFFA9B2BB),
      kUnsortedBucket => const Color(0xFFCDD3D8),
      _ when isCustomCategory(bucket) => HSLColor.fromAHSL(
              1, (bucket.hashCode % 360).toDouble().abs(), 0.45, 0.55)
          .toColor(),
      _ => const Color(0xFF6E7B88),
    };

/// Black or white, whichever reads better on [c].
Color _onColor(Color c) =>
    c.computeLuminance() > 0.35 ? const Color(0xFF111418) : Colors.white;

/// "Where did my money go?" as a ring: each category's share of the last 7
/// days, with its percentage on the ring and a legend underneath. The ring
/// draws itself once when it appears.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({super.key, required this.totals});

  final List<CategoryTotal> totals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final total = totals.fold<int>(0, (a, t) => a + t.totalFils);
    if (total <= 0) return const SizedBox.shrink();
    String pct(CategoryTotal t) => '${(t.totalFils * 100 + total ~/ 2) ~/ total}%';
    final slices = [
      for (final t in totals)
        _Slice(t.totalFils / total, categoryColor(t.bucket), pct(t)),
    ];
    final description = [
      for (final t in totals) '${categoryName(l10n, t.bucket)} ${pct(t)}',
    ].join('، ');
    return Card(
      key: const Key('categoryDonut'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.weekWhereTitle, style: theme.textTheme.titleMedium),
            Text(l10n.weekWhereSubtitle(l10n.bhd(formatFils(total))),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Center(
              child: Semantics(
                label: description,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: motion(context, const Duration(milliseconds: 800)),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => SizedBox.square(
                    dimension: 220,
                    child: CustomPaint(
                      painter: _DonutPainter(
                        slices,
                        progress: t,
                        track: theme.colorScheme.surfaceContainerHighest,
                        labelStyle: theme.textTheme.labelMedium!
                            .copyWith(fontWeight: FontWeight.w700),
                        textDirection: Directionality.of(context),
                      ),
                      child: Center(
                        child: Opacity(
                          opacity: t,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(formatFils(total),
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              Text(l10n.currencyShort,
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final t in totals)
              Padding(
                key: Key('donut_${t.bucket}'),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: categoryColor(t.bucket),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(categoryIcon(t.bucket), size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(categoryName(l10n, t.bucket))),
                    Text(l10n.bhd(formatFils(t.totalFils))),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 40,
                      child: Text(pct(t),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Slice {
  const _Slice(this.share, this.color, this.label);
  final double share;
  final Color color;
  final String label;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(
    this.slices, {
    required this.progress,
    required this.track,
    required this.labelStyle,
    required this.textDirection,
  });

  final List<_Slice> slices;
  final double progress;
  final Color track;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  static const double _ring = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _ring / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ring
          ..color = track);
    // Clockwise from 12 o'clock; a hair of space between slices.
    var start = -math.pi / 2;
    const gap = 0.02;
    final sweepAll = 2 * math.pi * progress;
    for (final s in slices) {
      final sweep = 2 * math.pi * s.share;
      final drawn = math.min(sweep, math.max(0.0, -math.pi / 2 + sweepAll - start));
      if (drawn > gap) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          drawn - gap,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _ring
            ..color = s.color,
        );
      }
      // The percentage sits on its slice, once the slice is drawn and big
      // enough to hold it (small ones are in the legend).
      if (progress >= 1 && s.share >= 0.06) {
        final mid = start + sweep / 2;
        final at = center + Offset(math.cos(mid), math.sin(mid)) * radius;
        final tp = TextPainter(
          text: TextSpan(
              text: s.label, style: labelStyle.copyWith(color: _onColor(s.color))),
          textDirection: textDirection,
        )..layout();
        tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.slices != slices || old.track != track;
}
