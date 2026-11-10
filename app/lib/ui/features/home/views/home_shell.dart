import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/sync_repository.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/core/language_controller.dart';
import 'package:beaza/ui/features/challenge/view_models/challenge_view_model.dart';
import 'package:beaza/ui/features/history/view_models/history_view_model.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/home/views/home_view.dart';
import 'package:flutter/material.dart';

/// The app's frame: Today, History and Insights behind a bottom bar, one
/// job per screen. Keeps the selected tab and the history list.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.viewModel,
    this.language,
    this.account,
    this.sync,
  });

  final HomeViewModel viewModel;
  final LanguageController? language;
  final AccountRepository? account;
  final SyncRepository? sync;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  HistoryViewModel? _history;

  @override
  void dispose() {
    _history?.dispose();
    super.dispose();
  }

  void _select(int tab) {
    if (tab == 1 && _history == null) {
      _history = HistoryViewModel(
        ledger: widget.viewModel.ledger,
        autoSort: widget.viewModel.autoSort,
      )..load();
    }
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motion(context, const Duration(milliseconds: 220)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: HomeView(
        key: ValueKey(_tab),
        viewModel: widget.viewModel,
        language: widget.language,
        account: widget.account,
        sync: widget.sync,
        tab: _tab,
        onTab: _select,
        history: _history,
      ),
    );
  }
}

/// [d], or nothing when the phone asks for less motion.
Duration motion(BuildContext context, Duration d) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;

/// Rises into place a little after the item before it, once.
class Rise extends StatelessWidget {
  const Rise({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ms = 260 + 40 * (index > 8 ? 8 : index);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, Duration(milliseconds: ms)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

/// Two reasons to open the app each day: the AI savings plan, one tap
/// away, and this week's challenge (which opens Insights).
class TodayTiles extends StatelessWidget {
  const TodayTiles({
    super.key,
    this.challenge,
    this.onOpen,
    this.onPlan,
  });

  final ChallengeViewModel? challenge;
  final VoidCallback? onOpen;

  /// Asks for the AI plan; null hides that tile.
  final VoidCallback? onPlan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = challenge;
    Widget tile(Key key, String title, String value, String hint,
            {VoidCallback? onTap, IconData? icon}) =>
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(12),
              onTap: onTap ?? onOpen,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 16),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(title,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(hint, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        );
    Widget challengeTile() {
      final active = c?.active;
      final p = c?.progress;
      if (active == null || p == null) {
        return tile(const Key('challengeTile'), l10n.challengeTitle,
            l10n.challengeTileNone, l10n.challengeTileStart);
      }
      final value = active.countsMoney
          ? '${formatFils(p.value)} / ${formatFils(active.target)}'
          : '${p.value} / ${active.target}';
      return tile(const Key('challengeTile'), l10n.challengeTitle, value,
          l10n.challengeTileDays(p.daysLeft));
    }

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onPlan != null) ...[
          tile(const Key('planTile'), l10n.coachTitle, l10n.planTileValue,
              l10n.planTileHint,
              onTap: onPlan, icon: Icons.auto_awesome_outlined),
          const SizedBox(width: 8),
        ],
        if (c == null)
          const Spacer()
        else
          ListenableBuilder(
            listenable: c,
            builder: (context, _) => challengeTile(),
          ),
      ],
    );
    return IntrinsicHeight(child: row);
  }
}
