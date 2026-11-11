import 'package:beaza/data/repositories/rewards_repository.dart';
import 'package:beaza/domain/use_cases/rewards.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:flutter/material.dart';

/// The demo offer a redemption was for, or null for an offer that no
/// longer exists.
DemoOffer? offerOf(Redemption r) {
  for (final o in kDemoOffers) {
    if (o.id == r.offerId) return o;
  }
  return null;
}

/// A redeemed demo voucher: code, a drawn stand-in for a QR code, days left
/// and the demo notice (FR-9.5).
Future<void> showVoucherSheet(
    BuildContext context, Redemption r, DateTime now) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final ar = Localizations.localeOf(context).languageCode == 'ar';
  final o = offerOf(r);
  final left = r.daysLeft(now);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        key: const Key('voucherSheet'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (o != null) ...[
              Text(ar ? o.partnerAr : o.partnerEn,
                  style: theme.textTheme.titleLarge),
              Text(ar ? o.offerAr : o.offerEn),
            ],
            const SizedBox(height: 16),
            Center(
              child: Opacity(
                opacity: left > 0 ? 1 : 0.35,
                child: CustomPaint(
                  key: const Key('voucherQr'),
                  size: const Size.square(150),
                  painter: DemoQrPainter(r.code,
                      ink: theme.colorScheme.onSurface,
                      paper: theme.colorScheme.surface),
                ),
              ),
            ),
            Center(
              child: Text(l10n.voucherQrNote, style: theme.textTheme.labelSmall),
            ),
            const SizedBox(height: 12),
            Center(
              child: SelectableText(r.code,
                  key: const Key('redeemCode'),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                left > 0 ? l10n.voucherDaysLeft(left) : l10n.voucherExpired,
                key: const Key('voucherExpiry'),
                style: TextStyle(
                    color: left > 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(l10n.voucherDisclaimer,
                  key: const Key('voucherDisclaimer'),
                  style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A square pattern made from the code, standing in for a QR code. It is
/// not a real QR code and nothing can scan it (the voucher is a demo).
class DemoQrPainter extends CustomPainter {
  DemoQrPainter(this.code, {required this.ink, required this.paper});

  final String code;
  final Color ink;
  final Color paper;

  static const int cells = 21;

  /// Same code, same pattern: FNV-1a of the code drives a small generator.
  static List<bool> pattern(String code) {
    var h = 0x811c9dc5;
    for (final c in code.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    final out = <bool>[];
    for (var i = 0; i < cells * cells; i++) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      out.add((h >> 16) & 1 == 1);
    }
    return out;
  }

  bool _finder(int x, int y) {
    bool inBox(int x0, int y0) {
      final dx = x - x0, dy = y - y0;
      if (dx < 0 || dy < 0 || dx > 6 || dy > 6) return false;
      final edge = dx == 0 || dy == 0 || dx == 6 || dy == 6;
      final core = dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4;
      return edge || core;
    }

    return inBox(0, 0) || inBox(cells - 7, 0) || inBox(0, cells - 7);
  }

  bool _nearFinder(int x, int y) =>
      (x < 8 && y < 8) || (x >= cells - 8 && y < 8) || (x < 8 && y >= cells - 8);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cells;
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    final dot = Paint()..color = ink;
    final bits = pattern(code);
    for (var y = 0; y < cells; y++) {
      for (var x = 0; x < cells; x++) {
        final on = _nearFinder(x, y) ? _finder(x, y) : bits[y * cells + x];
        if (on) {
          canvas.drawRect(
              Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(DemoQrPainter old) =>
      old.code != code || old.ink != ink || old.paper != paper;
}

/// "My coupons": every redeemed demo voucher, newest first.
class RedeemedVouchersScreen extends StatelessWidget {
  const RedeemedVouchersScreen({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.walletTitle)),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final list = viewModel.vouchers;
          final now = viewModel.now();
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.walletEmpty,
                    key: const Key('walletEmpty'), textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            key: const Key('walletList'),
            padding: const EdgeInsets.all(12),
            children: [
              for (final r in list)
                Card(
                  child: ListTile(
                    key: Key('voucher_${r.code}'),
                    leading: Icon(categoryIcon(offerOf(r)?.category ?? 'other')),
                    title: Text(offerOf(r) == null
                        ? r.code
                        : (ar ? offerOf(r)!.offerAr : offerOf(r)!.offerEn)),
                    subtitle: Text(
                        '${offerOf(r) == null ? '' : '${ar ? offerOf(r)!.partnerAr : offerOf(r)!.partnerEn} · '}${r.code}'),
                    trailing: Text(
                      r.activeAt(now)
                          ? l10n.voucherDaysLeft(r.daysLeft(now))
                          : l10n.voucherExpired,
                      style: TextStyle(
                          color: r.activeAt(now)
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error),
                    ),
                    onTap: () => showVoucherSheet(context, r, now),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
