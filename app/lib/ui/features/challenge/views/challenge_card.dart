import 'package:beaza/domain/use_cases/weekly_challenge.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/challenge/view_models/challenge_view_model.dart';
import 'package:flutter/material.dart';

/// "This week's challenge": one small goal from last week's weak spot.
class ChallengeCard extends StatelessWidget {
  const ChallengeCard({super.key, required this.viewModel});

  final ChallengeViewModel viewModel;

  static String describe(AppLocalizations l10n, Challenge c) {
    String money(int fils) => l10n.bhd(formatFils(fils));
    final saving = money(c.savingFils);
    return switch (c.kind) {
      ChallengeKind.shop =>
        l10n.challengeShop(c.shop ?? '-', c.target, saving),
      ChallengeKind.lateNight => l10n.challengeLate(saving),
      ChallengeKind.small => l10n.challengeSmall(c.target, saving),
      ChallengeKind.category => l10n.challengeCategory(
          categoryName(l10n, c.category ?? 'other'), money(c.target), saving),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final active = viewModel.active;
        final suggestion = viewModel.suggestion;
        if (active == null && suggestion == null) return const SizedBox.shrink();
        final children = <Widget>[
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.challengeTitle,
                    style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ];
        if (active == null) {
          children.addAll([
            Text(describe(l10n, suggestion!), key: const Key('challengeText')),
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: const Key('challengeAccept'),
              onPressed: viewModel.accept,
              child: Text(l10n.challengeAccept),
            ),
          ]);
        } else {
          final p = viewModel.progress!;
          String amount(int v) =>
              active.countsMoney ? l10n.bhd(formatFils(v)) : '$v';
          final over = !viewModel.kept;
          children.add(Text(describe(l10n, active), key: const Key('challengeText')));
          children.add(const SizedBox(height: 8));
          if (!p.finished) {
            children.add(Text(
              l10n.challengeProgress(
                  amount(p.value), amount(active.target), p.daysLeft),
              key: const Key('challengeProgress'),
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: over ? theme.colorScheme.error : null),
            ));
            children.add(Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('challengeStop'),
                onPressed: viewModel.clear,
                child: Text(l10n.challengeStop),
              ),
            ));
          } else {
            children.addAll([
              Text(viewModel.kept ? l10n.challengeWon : l10n.challengeLost,
                  key: const Key('challengeResult'),
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const Key('challengeNew'),
                onPressed: viewModel.clear,
                child: Text(l10n.challengeNew),
              ),
            ]);
          }
        }
        return Card(
          key: const Key('challengeCard'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        );
      },
    );
  }
}
