import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart' show Day;
import 'package:flutter/material.dart';

/// Goal, cooling-off shield (درع التريث) and repeating charges.
class SavingsView extends StatelessWidget {
  const SavingsView({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.savingsTitle)),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GoalCard(viewModel: viewModel),
            const SizedBox(height: 12),
            HoldsCard(viewModel: viewModel),
            const SizedBox(height: 12),
            SubscriptionsCard(viewModel: viewModel),
          ],
        ),
      ),
    );
  }
}

/// Asks for a name and an amount. Null when cancelled.
Future<(String, int)?> askNameAmount(
  BuildContext context, {
  required String title,
  required String nameLabel,
  bool withName = true,
}) {
  final l10n = AppLocalizations.of(context);
  final name = TextEditingController();
  final amount = TextEditingController();
  return showDialog<(String, int)>(
    context: context,
    builder: (context) {
      var invalid = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (withName)
                TextField(
                  key: const Key('nameField'),
                  controller: name,
                  decoration: InputDecoration(labelText: nameLabel),
                ),
              TextField(
                key: const Key('amountField'),
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.receiptAmount,
                  errorText: invalid ? l10n.receiptInvalid : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.coachNotNow),
            ),
            FilledButton(
              key: const Key('dialogSave'),
              onPressed: () {
                final fils = parseBhdToFils(amount.text);
                final n = name.text.trim();
                if (fils == null || (withName && n.isEmpty)) {
                  setState(() => invalid = true);
                  return;
                }
                Navigator.of(context).pop((n, fils));
              },
              child: Text(l10n.receiptSave),
            ),
          ],
        ),
      );
    },
  );
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final goal = viewModel.goal;
    String money(int f) => l10n.bhd(formatFils(f));
    return Card(
      key: const Key('goalCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.flag_outlined),
              const SizedBox(width: 8),
              Text(l10n.goalTitle, style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            if (goal == null) ...[
              Text(l10n.goalEmpty, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const Key('goalSet'),
                onPressed: () async {
                  final r = await askNameAmount(context,
                      title: l10n.goalSet, nameLabel: l10n.goalName);
                  if (r != null) await viewModel.repo.setGoal(r.$1, r.$2);
                },
                child: Text(l10n.goalSet),
              ),
            ] else ...[
              Text(goal.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  key: const Key('goalProgress'),
                  value: (viewModel.goalSaved / goal.targetFils).clamp(0.0, 1.0),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 6),
              Text(l10n.goalProgress(money(viewModel.goalSaved), money(goal.targetFils))),
              if (viewModel.goalSaved >= goal.targetFils)
                Text(l10n.goalReached, style: TextStyle(color: theme.colorScheme.primary)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton.tonal(
                  key: const Key('goalAdd'),
                  onPressed: () async {
                    final r = await askNameAmount(context,
                        title: l10n.goalAdd, nameLabel: '', withName: false);
                    if (r != null) await viewModel.repo.addToGoal(r.$2);
                  },
                  child: Text(l10n.goalAdd),
                ),
                TextButton(
                  key: const Key('goalClear'),
                  onPressed: viewModel.repo.clearGoal,
                  child: Text(l10n.goalClear),
                ),
              ]),
              Text(l10n.goalHow, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class HoldsCard extends StatelessWidget {
  const HoldsCard({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = viewModel.now();
    String money(int f) => l10n.bhd(formatFils(f));
    return Card(
      key: const Key('holdsCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.shield_outlined),
              const SizedBox(width: 8),
              Text(l10n.holdTitle, style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text(l10n.holdExplain, style: theme.textTheme.bodySmall),
            if (viewModel.skippedTotal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l10n.holdSaved(money(viewModel.skippedTotal)),
                    key: const Key('holdSaved'),
                    style: TextStyle(color: theme.colorScheme.primary)),
              ),
            for (final h in viewModel.waiting)
              ListTile(
                key: Key('hold_${h.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(h.readyAt(now) ? Icons.check_circle_outline : Icons.hourglass_top),
                title: Text(h.name),
                subtitle: Text(h.readyAt(now)
                    ? l10n.holdReady
                    : l10n.holdLeft((h.leftAt(now).inMinutes / 60).ceil())),
                trailing: h.readyAt(now)
                    ? Wrap(spacing: 4, children: [
                        TextButton(
                          key: Key('skip_${h.id}'),
                          onPressed: () => viewModel.repo.decide(h.id, 'skipped'),
                          child: Text(l10n.holdSkip),
                        ),
                        TextButton(
                          key: Key('buy_${h.id}'),
                          onPressed: () => viewModel.repo.decide(h.id, 'bought'),
                          child: Text(l10n.holdBuy),
                        ),
                      ])
                    : Text(money(h.amountFils)),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('holdAdd'),
              onPressed: () async {
                final r = await askNameAmount(context,
                    title: l10n.holdAdd, nameLabel: l10n.holdName);
                if (r != null) await viewModel.repo.addHold(r.$1, r.$2);
              },
              icon: const Icon(Icons.add),
              label: Text(l10n.holdAdd),
            ),
          ],
        ),
      ),
    );
  }
}

class SubscriptionsCard extends StatelessWidget {
  const SubscriptionsCard({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String money(int f) => l10n.bhd(formatFils(f));
    final subs = viewModel.subscriptions;
    return Card(
      key: const Key('subsCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.autorenew),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.subsTitle, style: theme.textTheme.titleMedium)),
              if (subs.isNotEmpty)
                Text(l10n.subsMonthly(money(viewModel.subscriptionsMonthly)),
                    key: const Key('subsTotal'), style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 4),
            if (subs.isEmpty)
              Text(l10n.subsEmpty, style: theme.textTheme.bodySmall),
            for (final s in subs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.name),
                subtitle: Text(s.knownByName
                    ? l10n.subsKnownOnce('${Day.of(s.next).day}/${Day.of(s.next).month}')
                    : l10n.subsLine(
                        s.weekly ? l10n.subsWeekly : l10n.subsMonth,
                        s.times,
                        '${Day.of(s.next).day}/${Day.of(s.next).month}',
                      )),
                trailing: Text(money(s.amountFils)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The home screen's way in: goal progress, holds waiting, subscriptions.
class SavingsHomeCard extends StatelessWidget {
  const SavingsHomeCard({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String money(int f) => l10n.bhd(formatFils(f));
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final goal = viewModel.goal;
        return Card(
          key: const Key('savingsCard'),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SavingsView(viewModel: viewModel),
            )),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.savings_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.savingsCardTitle,
                          style: theme.textTheme.titleMedium),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                  const SizedBox(height: 8),
                  if (goal == null)
                    Text(l10n.savingsCardNoGoal)
                  else ...[
                    Text(l10n.savingsCardGoal(goal.name,
                        money(viewModel.goalSaved), money(goal.targetFils))),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (viewModel.goalSaved / goal.targetFils)
                            .clamp(0.0, 1.0),
                        minHeight: 8,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (viewModel.waiting.isNotEmpty)
                        l10n.savingsCardHolds(viewModel.waiting.length),
                      if (viewModel.subscriptions.isNotEmpty)
                        l10n.savingsCardSubs(money(viewModel.subscriptionsMonthly)),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
