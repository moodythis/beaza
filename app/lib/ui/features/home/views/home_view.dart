import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/amount_dialog.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';

/// Home: spent versus limit, what is left, micro-expenses and today's list.
class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addExpense'),
        onPressed: () => _addExpense(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.addExpense),
      ),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final state = viewModel.state;
          if (state == null) {
            return Center(
              child: viewModel.error != null
                  ? Text(l10n.loadError)
                  : const CircularProgressIndicator(),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              LimitCard(
                summary: state.summary,
                onEditLimit: () => _editLimit(context),
              ),
              const SizedBox(height: 12),
              MicroCard(today: state.summary.micro, week: state.weekMicro),
              const SizedBox(height: 20),
              Text(
                l10n.todaySpendingTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (state.today.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(l10n.emptyToday, textAlign: TextAlign.center),
                )
              else
                for (final entry in state.today) EntryTile(entry: entry),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addExpense(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final input = await showAmountDialog(
      context,
      title: l10n.addExpense,
      withMerchant: true,
    );
    if (input == null) return;
    await viewModel.addExpense(amountFils: input.fils, merchant: input.merchant);
  }

  Future<void> _editLimit(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final current = viewModel.state?.summary.baseLimitFils ?? 0;
    final input = await showAmountDialog(
      context,
      title: l10n.dailyLimit,
      initialFils: current > 0 ? current : null,
    );
    if (input == null) return;
    await viewModel.setDailyLimit(input.fils);
  }
}

class LimitCard extends StatelessWidget {
  const LimitCard({
    super.key,
    required this.summary,
    required this.onEditLimit,
  });

  final DaySummary summary;
  final VoidCallback onEditLimit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spent = l10n.bhd(formatFils(summary.spentFils));

    if (summary.limitFils <= 0) {
      return Card(
        child: ListTile(
          key: const Key('setLimit'),
          title: Text(l10n.setLimitTitle),
          subtitle: Text(l10n.spentToday(spent)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onEditLimit,
        ),
      );
    }

    final over = summary.remainingFils < 0;
    final color = levelColor(theme.colorScheme, summary.level);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    over ? l10n.overLimitLabel : l10n.remainingLabel,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const Key('editLimit'),
                  tooltip: l10n.editLimit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEditLimit,
                ),
              ],
            ),
            Text(
              l10n.bhd(formatFils(summary.remainingFils.abs())),
              key: const Key('remaining'),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: over ? theme.colorScheme.error : null,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (summary.spentFils / summary.limitFils).clamp(0.0, 1.0),
                minHeight: 10,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.spentOfLimit(
                spent,
                l10n.bhd(formatFils(summary.limitFils)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              levelText(l10n, summary.level),
              key: const Key('level'),
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Calm colors on purpose: alerts inform, they do not blame.
Color levelColor(ColorScheme scheme, AlertLevel level) => switch (level) {
      AlertLevel.normal || AlertLevel.level1 => scheme.primary,
      AlertLevel.level2 => Colors.orange.shade800,
      AlertLevel.level3 => scheme.error,
    };

String levelText(AppLocalizations l10n, AlertLevel level) => switch (level) {
      AlertLevel.normal => l10n.levelNormal,
      AlertLevel.level1 => l10n.level1,
      AlertLevel.level2 => l10n.level2,
      AlertLevel.level3 => l10n.level3,
    };

class MicroCard extends StatelessWidget {
  const MicroCard({super.key, required this.today, required this.week});

  final MicroStats today;
  final MicroStats week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.local_cafe_outlined),
        title: Text(
          l10n.microToday(today.count, l10n.bhd(formatFils(today.totalFils))),
        ),
        subtitle: Text(l10n.microWeek(l10n.bhd(formatFils(week.totalFils)))),
      ),
    );
  }
}

class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = entry.result;
    final at = r.timestamp;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(r.merchantRaw ?? l10n.unknownMerchant),
      subtitle: at == null ? null : Text(formatBahrainTime(at)),
      trailing: Text(
        l10n.bhd(formatFils(r.amountFils ?? 0)),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}
