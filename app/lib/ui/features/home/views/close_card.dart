import 'package:beaza/domain/use_cases/daily_close.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/coin_flight.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/views/home_shell.dart';
import 'package:flutter/material.dart';

/// The daily close: what is left of a day's limit, and two places to put
/// it. One tap each; coins fly to where it went.
class CloseCard extends StatelessWidget {
  const CloseCard({
    super.key,
    required this.offer,
    required this.goalName,
    required this.baseLimitFils,
    required this.onClose,
    this.onSetGoal,
  });

  final CloseOffer offer;

  /// The savings goal's name; null when there is no goal yet.
  final String? goalName;

  /// The daily limit a carried-over surplus is capped against.
  final int baseLimitFils;

  /// Closes the day and returns the fils moved (0 when nothing was).
  final Future<int> Function(CloseKind kind) onClose;

  /// Opens the Saving tab to set a goal.
  final VoidCallback? onSetGoal;

  Future<void> _close(BuildContext context, CloseKind kind) async {
    // Everything the flight needs is read before the card goes away.
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final media = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final duration = motion(context, CoinFlight.duration);
    final box = context.findRenderObject();
    final from = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    final fils = await onClose(kind);
    if (fils <= 0) return;
    final amount = l10n.bhd(formatFils(fils));
    final size = media.size;
    // The Saving tab is the last of the four in the bottom bar; "tomorrow"
    // is the limit at the top of the screen.
    final to = kind == CloseKind.goal
        ? Offset(rtl ? size.width / 8 : size.width * 7 / 8,
            size.height - media.viewPadding.bottom - 52)
        : Offset(size.width / 2, media.viewPadding.top + kToolbarHeight + 48);
    if (from != null && overlay != null) {
      CoinFlight.show(overlay,
          from: from, to: to, label: '+$amount', duration: duration);
    }
    messenger.showSnackBar(SnackBar(
      content: Text(kind == CloseKind.goal
          ? l10n.closedGoal(amount, kClosePoints)
          : offer.yesterday
              ? l10n.closedRolloverToday(amount)
              : l10n.closedRollover(amount)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String money(int f) => l10n.bhd(formatFils(f));
    final carry = offer.rolloverFils(baseLimitFils);
    return Card(
      key: const Key('closeCard'),
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.nightlight_round,
                  color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    offer.yesterday
                        ? l10n.closeTitleYesterday
                        : l10n.closeTitleToday,
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(l10n.closeLeft(money(offer.surplusFils)),
                key: const Key('closeLeft'),
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            if (offer.noSpending)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.closeNoSpending,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer)),
              ),
            const SizedBox(height: 12),
            if (goalName != null)
              FilledButton.icon(
                key: const Key('closeGoal'),
                icon: const Icon(Icons.savings_outlined),
                label: Text(l10n.closeGoal(goalName!, kClosePoints)),
                onPressed: () => _close(context, CloseKind.goal),
              )
            else
              FilledButton.tonalIcon(
                key: const Key('closeSetGoal'),
                icon: const Icon(Icons.flag_outlined),
                label: Text(l10n.closeSetGoal),
                onPressed: onSetGoal,
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('closeRollover'),
              icon: const Icon(Icons.redo),
              label: Text(offer.yesterday
                  ? l10n.closeRolloverToday(money(carry))
                  : l10n.closeRollover(money(carry))),
              onPressed:
                  carry <= 0 ? null : () => _close(context, CloseKind.rollover),
            ),
            if (carry < offer.surplusFils)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l10n.closeRolloverCapped,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer)),
              ),
            const SizedBox(height: 6),
            Text(l10n.closeDoneHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          ],
        ),
      ),
    );
  }
}
