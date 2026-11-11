import 'package:beaza/data/repositories/rewards_repository.dart' show Redemption;
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza/ui/features/savings/views/vouchers.dart';
import 'package:beaza/ui/features/savings/views/leaderboard_card.dart';
import 'package:beaza_extraction/beaza_extraction.dart' show Day;
import 'package:beaza/ui/core/privacy_button.dart';
import 'package:flutter/material.dart';

/// Goal, cooling-off shield (درع التريث) and repeating charges.
class SavingsView extends StatelessWidget {
  const SavingsView({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.savingsTitle),
        actions: const [PrivacyButton()],
      ),
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
            if (viewModel.rewards != null) ...[
              const SizedBox(height: 12),
              RewardsCard(viewModel: viewModel),
              const SizedBox(height: 12),
              LeaderboardCard(viewModel: viewModel),
            ],
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

/// Name, amount, monthly or weekly, and the day it was last paid. Null
/// when cancelled.
Future<(String, int, bool, Day)?> askSubscription(
    BuildContext context, DateTime now) {
  return showDialog<(String, int, bool, Day)>(
    context: context,
    builder: (context) => _SubscriptionDialog(today: Day.of(now)),
  );
}

class _SubscriptionDialog extends StatefulWidget {
  const _SubscriptionDialog({required this.today});

  final Day today;

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  bool _weekly = false;
  late Day _last = widget.today;
  bool _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shown = MaterialLocalizations.of(context).formatMediumDate(
        DateTime(_last.year, _last.month, _last.day));
    return AlertDialog(
      title: Text(l10n.subsAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('subName'),
              controller: _name,
              decoration: InputDecoration(labelText: l10n.subsName),
            ),
            TextField(
              key: const Key('subAmount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.receiptAmount,
                errorText: _invalid ? l10n.receiptInvalid : null,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              key: const Key('subEvery'),
              segments: [
                ButtonSegment(value: false, label: Text(l10n.subsMonth)),
                ButtonSegment(
                    value: true,
                    label: Text(l10n.subsWeekly, key: const Key('subWeekly'))),
              ],
              selected: {_weekly},
              onSelectionChanged: (v) => setState(() => _weekly = v.first),
            ),
            const SizedBox(height: 4),
            ListTile(
              key: const Key('subLastPaid'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(l10n.subsLastPaid(shown)),
              onTap: () async {
                final t = widget.today;
                final picked = await showDatePicker(
                  context: context,
                  locale: Localizations.localeOf(context),
                  initialDate: DateTime(_last.year, _last.month, _last.day),
                  firstDate: DateTime(t.year - 1, t.month, t.day),
                  lastDate: DateTime(t.year, t.month, t.day),
                );
                if (picked != null) {
                  setState(() => _last = Day(picked.year, picked.month, picked.day));
                }
              },
            ),
            Text(l10n.subsReminderOnly,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coachNotNow),
        ),
        FilledButton(
          key: const Key('subSave'),
          onPressed: () {
            final fils = parseBhdToFils(_amount.text);
            final n = _name.text.trim();
            if (fils == null || fils <= 0 || n.isEmpty) {
              setState(() => _invalid = true);
              return;
            }
            Navigator.of(context).pop((n, fils, _weekly, _last));
          },
          child: Text(l10n.receiptSave),
        ),
      ],
    );
  }
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
              Expanded(
                  child: Text(l10n.holdTitle,
                      style: theme.textTheme.titleMedium)),
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
                key: s.manual ? Key('sub_${s.manualId}') : null,
                contentPadding: EdgeInsets.zero,
                title: Text(s.name),
                subtitle: Text(s.manual
                    ? l10n.subsManualLine(
                        s.weekly ? l10n.subsWeekly : l10n.subsMonth,
                        '${Day.of(s.next).day}/${Day.of(s.next).month}')
                    : s.knownByName
                        ? l10n.subsKnownOnce('${Day.of(s.next).day}/${Day.of(s.next).month}')
                        : l10n.subsLine(
                            s.weekly ? l10n.subsWeekly : l10n.subsMonth,
                            s.times,
                            '${Day.of(s.next).day}/${Day.of(s.next).month}',
                          )),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(money(s.amountFils)),
                    if (s.manual)
                      IconButton(
                        key: Key('subRemove_${s.manualId}'),
                        tooltip: l10n.subsRemove,
                        icon: const Icon(Icons.close),
                        onPressed: () => viewModel.removeSubscription(s.manualId!),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('subsAdd'),
                icon: const Icon(Icons.add),
                label: Text(l10n.subsAdd),
                onPressed: () async {
                  final r = await askSubscription(context, viewModel.now());
                  if (r == null) return;
                  await viewModel.addSubscription(r.$1, r.$2, r.$3, r.$4);
                },
              ),
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


/// DEMO points and offers: invented partners, clearly labelled.
class RewardsCard extends StatelessWidget {
  const RewardsCard({super.key, required this.viewModel});

  final SavingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final balance = viewModel.pointsBalance;
    return Card(
      key: const Key('rewardsCard'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                theme.colorScheme.primary.withValues(alpha: 0.35),
                theme.colorScheme.tertiary.withValues(alpha: 0.20),
              ]),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.rewardsPass, style: theme.textTheme.titleMedium),
                      Text(l10n.rewardsDemo, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$balance',
                        key: const Key('pointsBalance'),
                        style: theme.textTheme.headlineMedium?.copyWith(
                            color: theme.colorScheme.tertiary,
                            fontWeight: FontWeight.w800)),
                    Text(l10n.rewardsPoints, style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          StreakRow(viewModel: viewModel),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(l10n.rewardsHow, style: theme.textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(l10n.rewardsMarket,
                      key: const Key('rewardsMarket'),
                      style: theme.textTheme.titleMedium),
                ),
                TextButton.icon(
                  key: const Key('openWallet'),
                  icon: const Icon(Icons.confirmation_number_outlined),
                  label: Text(l10n.walletButton(viewModel.vouchers.length)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => RedeemedVouchersScreen(viewModel: viewModel))),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(l10n.dealsHow, style: theme.textTheme.bodySmall),
          ),
          SwitchListTile(
            key: const Key('offersPersonal'),
            value: viewModel.personalOffers,
            onChanged: (on) => viewModel.rewards!.setPersonal(on),
            title: Text(l10n.offersPersonal),
            subtitle: Text(l10n.offersPersonalHow),
          ),
          for (final o in viewModel.offers)
            ListTile(
              key: Key('offer_${o.id}'),
              leading: Icon(categoryIcon(o.category)),
              title: Text('${ar ? o.partnerAr : o.partnerEn} · ${l10n.rewardsDemoTag}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ar ? o.offerAr : o.offerEn),
                  if ((viewModel.fits[o.id]?.spentFils ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l10n.dealFit(
                          l10n.bhd(formatFils(viewModel.fits[o.id]!.spentFils)),
                          viewModel.fits[o.id]!.count,
                          l10n.bhd(formatFils(viewModel.fits[o.id]!.savingFils)),
                        ),
                        key: Key('dealFit_${o.id}'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Container(
                    key: Key('offerBadge_${o.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(categoryName(l10n, o.category),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer)),
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: FilledButton.tonal(
                key: Key('redeem_${o.id}'),
                onPressed: () async {
                  final held = viewModel.activeVoucher(o);
                  if (held != null) {
                    await showVoucherSheet(context, held, viewModel.now());
                    return;
                  }
                  final when = viewModel.now();
                  final code = await viewModel.redeem(o);
                  if (code == null || !context.mounted) return;
                  await showVoucherSheet(
                      context, Redemption(o.id, code, o.cost, when), when);
                },
                child: Text(viewModel.activeVoucher(o) != null
                    ? l10n.dealShow
                    : l10n.dealGet),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
