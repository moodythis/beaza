import 'dart:math' as math;

import 'package:beaza/domain/use_cases/leaderboard.dart';
import 'package:beaza/domain/use_cases/streak.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:beaza/ui/features/home/views/home_shell.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart' show Day;
import 'package:flutter/material.dart';

/// The persona title in the app's language.
String personaName(AppLocalizations l10n, PersonaTitle t) => switch (t) {
      PersonaTitle.guardian => l10n.personaGuardian,
      PersonaTitle.filsMaster => l10n.personaFilsMaster,
      PersonaTitle.captain => l10n.personaCaptain,
      PersonaTitle.falcon => l10n.personaFalcon,
    };

/// How a row is named: its nickname, or its persona title and number.
String boardName(AppLocalizations l10n, BoardRow r) =>
    r.nickname ?? '${personaName(l10n, r.title)} #${r.number}';

/// A flame that swells once each time the streak grows.
class StreakFlame extends StatefulWidget {
  const StreakFlame({super.key, required this.days, this.size = 28});

  final int days;
  final double size;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600), value: 1);

  @override
  void didUpdateWidget(StreakFlame old) {
    super.didUpdateWidget(old);
    if (widget.days > old.days) {
      final d = motion(context, const Duration(milliseconds: 600));
      if (d > Duration.zero) {
        _c.duration = d;
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lit = widget.days > 0;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.4 * math.sin(_c.value * math.pi),
        child: child,
      ),
      child: Icon(
        Icons.local_fire_department,
        key: const Key('streakFlame'),
        size: widget.size,
        color: lit ? const Color(0xFFE8731A) : theme.colorScheme.outline,
      ),
    );
  }
}

/// The streak and its freeze, shown with the points.
class StreakRow extends StatelessWidget {
  const StreakRow({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final used = viewModel.freezeUsedOn;
    final canBuy =
        !viewModel.freezeHeld && viewModel.pointsBalance >= kFreezeCost;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StreakFlame(days: viewModel.streak),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.streakDaysLabel(viewModel.streak),
                        key: const Key('streakDays'),
                        style: theme.textTheme.titleMedium),
                    Text(l10n.streakHow, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // On its own line: next to the title it ran off narrow screens.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: viewModel.freezeHeld
                ? Chip(
                    key: const Key('freezeHeld'),
                    avatar: const Icon(Icons.ac_unit, size: 18),
                    label: Text(l10n.freezeHeld),
                  )
                : FilledButton.tonalIcon(
                    key: const Key('freezeBuy'),
                    icon: const Icon(Icons.ac_unit, size: 18),
                    label: Text(l10n.freezeBuy(kFreezeCost)),
                    onPressed: canBuy ? viewModel.buyFreeze : null,
                  ),
          ),
          const SizedBox(height: 4),
          Text(l10n.freezeHow, style: theme.textTheme.bodySmall),
          if (used != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.freezeUsed(shortDay(used)),
                  key: const Key('freezeUsed'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
        ],
      ),
    );
  }
}

/// The leaderboard: points of the last 30 days and streak days, never
/// money. The practice board works on the phone; the online one is joined
/// with its own consent.
class LeaderboardCard extends StatelessWidget {
  const LeaderboardCard({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  /// Rows shown above the person's own when they are further down.
  static const int shown = 10;
  static const double rowHeight = 44;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final all = viewModel.boardRows;
    final myIndex = all.indexWhere((r) => r.me);
    final online = viewModel.boardOnline;
    // The top rows, and the person's own row under them when it is lower.
    final visible = <(int?, BoardRow)>[
      for (var i = 0; i < all.length && i < shown; i++) (i + 1, all[i]),
      if (myIndex >= shown)
        (online && viewModel.board?.rank == null ? null : myIndex + 1, all[myIndex]),
    ];
    final board = viewModel.board;
    final me = myIndex < 0 ? null : all[myIndex];
    return Card(
      key: const Key('boardCard'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Icon(Icons.emoji_events_outlined),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(l10n.boardTitle,
                        style: theme.textTheme.titleMedium)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                  '${online ? l10n.boardOnlineNote : l10n.boardPractice}\n${l10n.boardMetric}',
                  key: const Key('boardNote'),
                  style: theme.textTheme.bodySmall),
            ),
            if (board?.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(l10n.boardOffline,
                    key: const Key('boardOffline'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ),
            SizedBox(
              height: visible.length * rowHeight,
              child: Stack(
                children: [
                  for (final (slot, (rank, row)) in visible.indexed)
                    AnimatedPositionedDirectional(
                      key: ValueKey(row.id),
                      duration:
                          motion(context, const Duration(milliseconds: 450)),
                      curve: Curves.easeOutCubic,
                      top: slot * rowHeight,
                      start: 0,
                      end: 0,
                      height: rowHeight,
                      child: _BoardLine(rank: rank, row: row),
                    ),
                ],
              ),
            ),
            const Divider(height: 24),
            SwitchListTile(
              key: const Key('boardNickSwitch'),
              value: viewModel.nickname != null,
              title: Text(l10n.boardNicknameSwitch),
              subtitle: Text(viewModel.nickname ??
                  l10n.boardNicknameOff(me == null
                      ? ''
                      : '${personaName(l10n, me.title)} #${me.number}')),
              onChanged: (on) async {
                if (!on) {
                  await viewModel.setNickname(null);
                  return;
                }
                await showDialog<void>(
                  context: context,
                  builder: (_) => _NicknameDialog(viewModel: viewModel),
                );
              },
            ),
            if (board != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: board.joined
                    ? Row(children: [
                        Expanded(
                          child: Text(
                              board.rank == null
                                  ? (board.rows == null ? '' : l10n.boardOutside)
                                  : l10n.boardRank(board.rank!),
                              key: const Key('boardRank')),
                        ),
                        TextButton(
                          key: const Key('boardLeave'),
                          onPressed: viewModel.leaveBoard,
                          child: Text(l10n.boardLeave),
                        ),
                      ])
                    : Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          key: const Key('boardJoin'),
                          icon: const Icon(Icons.public),
                          label: Text(l10n.boardJoin),
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (_) => const _JoinDialog(),
                            );
                            if (yes == true) await viewModel.joinBoard();
                          },
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoardLine extends StatelessWidget {
  const _BoardLine({required this.rank, required this.row});

  /// Null when the place is outside what the server keeps.
  final int? rank;
  final BoardRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final emerald = theme.brightness == Brightness.dark
        ? const Color(0xFF3DD68C)
        : const Color(0xFF13804C);
    final style = row.me
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium;
    return Container(
      key: row.me ? const Key('boardMe') : null,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: row.me ? emerald.withValues(alpha: 0.14) : null,
        border: row.me ? Border.all(color: emerald, width: 1.5) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(rank == null ? '50+' : '$rank',
                style: style, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              row.me
                  ? '${boardName(l10n, row)} · ${l10n.boardYou}'
                  : boardName(l10n, row),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.local_fire_department,
              size: 16,
              color: row.streak > 0
                  ? const Color(0xFFE8731A)
                  : theme.colorScheme.outline),
          SizedBox(
            width: 26,
            child: Text('${row.streak}',
                style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 44,
            child: Text('${row.points}', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// Asks for the nickname and says why one is refused.
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  final _name = TextEditingController();
  NicknameProblem? _problem;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = switch (_problem) {
      null => null,
      NicknameProblem.tooShort => l10n.boardNickShort,
      NicknameProblem.tooLong => l10n.boardNickLong,
      NicknameProblem.notLetters => l10n.boardNickLetters,
    };
    return AlertDialog(
      title: Text(l10n.boardNicknameSwitch),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('boardNickField'),
            controller: _name,
            autofocus: true,
            maxLength: 15,
            decoration: InputDecoration(
              labelText: l10n.boardNicknameField,
              errorText: error,
              errorMaxLines: 3,
            ),
          ),
          Text(l10n.boardNickWarn,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coachNotNow),
        ),
        FilledButton(
          key: const Key('boardNickSave'),
          onPressed: () async {
            final navigator = Navigator.of(context);
            final problem = await widget.viewModel.setNickname(_name.text);
            if (problem == null) {
              navigator.pop();
            } else if (mounted) {
              setState(() => _problem = problem);
            }
          },
          child: Text(l10n.boardNickSave),
        ),
      ],
    );
  }
}

/// The consent for the online board: exactly what is sent, before joining.
class _JoinDialog extends StatelessWidget {
  const _JoinDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.boardJoin),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.boardJoinWhat, key: const Key('boardJoinWhat')),
            TextButton(
              key: const Key('boardPrivacy'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => openLegal(context, privacyNotice,
                  section: kPrivacyBoardSection),
              child: Text(l10n.privacyDetails),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.coachNotNow),
        ),
        FilledButton(
          key: const Key('boardJoinAgree'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.boardJoinAgree),
        ),
      ],
    );
  }
}

/// The day shown in "used on" lines.
String shortDay(Day d) => '${d.day}/${d.month}';
