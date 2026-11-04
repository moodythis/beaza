import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/sync_repository.dart';
import 'package:beaza/domain/use_cases/savings_tips.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/alert_text.dart';
import 'package:beaza/ui/core/amount_dialog.dart';
import 'package:beaza/ui/core/category_picker.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/entry_text.dart';
import 'package:beaza/ui/core/entry_tile.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/core/language_controller.dart';
import 'package:beaza/ui/features/account/views/account_view.dart';
import 'package:beaza/ui/features/history/view_models/history_view_model.dart';
import 'package:beaza/ui/features/history/views/history_view.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/home/views/quick_add_sheet.dart';
import 'package:beaza/ui/features/receipt/view_models/receipt_view_model.dart';
import 'package:beaza/ui/features/receipt/views/receipt_sheet.dart';
import 'package:beaza/ui/features/review/view_models/review_view_model.dart';
import 'package:beaza/ui/features/review/views/review_view.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';

/// Home: spent versus limit, what is left, micro-expenses and today's list.
class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.viewModel,
    this.language,
    this.account,
    this.sync,
  });

  final HomeViewModel viewModel;

  /// Null hides the language button.
  final LanguageController? language;

  /// Null hides the account button.
  final AccountRepository? account;

  /// Sync status and the "Sync now" button on the account screen.
  final SyncRepository? sync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          if (language != null)
            TextButton.icon(
              key: const Key('languageButton'),
              icon: const Icon(Icons.translate),
              // Shows the other language, written in that language.
              label: Text(l10n.otherLanguage),
              onPressed: () => language!.choose(
                Localizations.localeOf(context).languageCode == 'ar'
                    ? 'en'
                    : 'ar',
              ),
            ),
          IconButton(
            key: const Key('historyButton'),
            tooltip: l10n.historyButton,
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HistoryView(
                  viewModel: HistoryViewModel(ledger: viewModel.ledger)..load(),
                ),
              ),
            ),
          ),
          if (account != null)
            ListenableBuilder(
              listenable: Listenable.merge([account!, if (sync != null) sync!]),
              builder: (context, _) => IconButton(
                key: const Key('accountButton'),
                tooltip: l10n.accountTitle,
                icon: Icon(!account!.signedIn
                    ? Icons.account_circle_outlined
                    : sync?.mergeCount != null || sync?.failure != null
                        ? Icons.sync_problem_outlined
                        : Icons.cloud_done_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AccountView(
                      repository: account!,
                      sync: sync,
                      export: viewModel.export,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (viewModel.receipts != null) ...[
            FloatingActionButton.small(
              key: const Key('addReceipt'),
              heroTag: 'addReceipt',
              tooltip: l10n.receiptTitle,
              onPressed: () => showReceiptSheet(
                context,
                ReceiptViewModel(
                  scanner: viewModel.receipts!,
                  ledger: viewModel.ledger,
                  clock: viewModel.now,
                ),
              ),
              child: const Icon(Icons.receipt_long_outlined),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton.small(
            key: const Key('quickAdd'),
            heroTag: 'quickAdd',
            tooltip: l10n.quickAddTitle,
            onPressed: () => showQuickAdd(context, viewModel),
            child: const Icon(Icons.keyboard_voice_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            key: const Key('addExpense'),
            heroTag: 'addExpense',
            onPressed: () => _addExpense(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.addExpense),
          ),
        ],
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
              if (viewModel.smsAllowed == false) ...[
                const SizedBox(height: 12),
                SmsCard(
                  denied: viewModel.smsDenied,
                  onAllow: viewModel.enableMessages,
                ),
              ],
              if (viewModel.batteryRestricted &&
                  viewModel.smsAllowed == true) ...[
                const SizedBox(height: 12),
                BatteryCard(onOpen: viewModel.openBatterySettings),
              ],
              const SizedBox(height: 12),
              MicroCard(today: state.summary.micro, week: state.weekMicro),
              const SizedBox(height: 12),
              CategoryCard(totals: state.weekByCategory),
              if (viewModel.duplicates > 0)
                Card(
                  key: const Key('duplicatesCard'),
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l10n.duplicatesFound(viewModel.duplicates)),
                        const SizedBox(height: 8),
                        FilledButton(
                          key: const Key('removeDuplicates'),
                          onPressed: viewModel.removeDuplicates,
                          child: Text(l10n.removeDuplicates),
                        ),
                      ],
                    ),
                  ),
                ),
              if (viewModel.notUnderstood > 0 && viewModel.intake != null)
                ListTile(
                  key: const Key('notUnderstood'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.help_outline),
                  title: Text(l10n.notUnderstood(viewModel.notUnderstood)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReviewView(
                        viewModel: ReviewViewModel(viewModel.intake!)..load(),
                      ),
                    ),
                  ),
                ),
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
                for (final entry in state.today)
                  EntryTile(
                    entry: entry,
                    onTap: () => _chooseCategory(context, entry),
                  ),
              // Tips come after today's list, which matters most.
              if (state.tips.isNotEmpty ||
                  adviceText(l10n, state.summary.level) != null) ...[
                const SizedBox(height: 12),
                TipsCard(tips: state.tips, level: state.summary.level),
              ],
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

  Future<void> _chooseCategory(BuildContext context, LedgerEntry entry) async {
    final current = bucketOf(entry.result);
    final picked = await pickCategory(
      context,
      current: current,
      shop: shopName(entry.result),
    );
    if (picked == null || picked == current) return;
    await viewModel.setCategory(entry, picked);
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

/// Asks for the SMS permission and says what is read.
class SmsCard extends StatelessWidget {
  const SmsCard({super.key, required this.denied, required this.onAllow});

  final bool denied;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const Key('smsCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sms_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(l10n.smsTitle, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(denied ? l10n.smsDenied : l10n.smsBody),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                key: const Key('smsAllow'),
                onPressed: onAllow,
                child: Text(l10n.smsAllow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Battery saving stops Beaza while it is closed, so alerts arrive late.
/// Shown only when SMS reading is on, since that is what it affects.
class BatteryCard extends StatelessWidget {
  const BatteryCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const Key('batteryCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.battery_alert_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(l10n.batteryTitle,
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.batteryBody),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                key: const Key('batteryOpen'),
                onPressed: onOpen,
                child: Text(l10n.batteryOpen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

/// Saving tips worked out by rules on this phone.
class TipsCard extends StatelessWidget {
  const TipsCard({
    super.key,
    required this.tips,
    this.level = AlertLevel.normal,
  });

  final List<SavingsTip> tips;

  /// Today's guardrail level: from 50% a short tip comes first.
  final AlertLevel level;

  static String text(AppLocalizations l10n, SavingsTip t) {
    String money(int fils) => l10n.bhd(formatFils(fils));
    final category = categoryName(l10n, t.bucket ?? 'other');
    return switch (t.kind) {
      TipKind.categorySpike =>
        l10n.tipSpike(category, money(t.fils), money(t.otherFils)),
      TipKind.overLimitDays => l10n.tipOverLimit(t.count),
      TipKind.smallPurchases => l10n.tipSmall(t.count, money(t.fils)),
      TipKind.topCategory => l10n.tipTop(category, t.count, money(t.fils)),
      TipKind.trimTarget => l10n.tipTrim(category, money(t.fils)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const Key('tipsCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 20),
                const SizedBox(width: 8),
                Text(l10n.tipsTitle, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 2),
            Text(l10n.tipsSubtitle, style: theme.textTheme.bodySmall),
            if (adviceText(l10n, level) case final advice?) ...[
              const SizedBox(height: 12),
              Row(
                key: const Key('tip_level'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.speed_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(advice)),
                ],
              ),
            ],
            for (var i = 0; i < tips.length; i++) ...[
              const SizedBox(height: 12),
              Row(
                key: Key('tip_$i'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    tips[i].kind == TipKind.smallPurchases
                        ? Icons.coffee_outlined
                        : tips[i].bucket == null
                        ? Icons.warning_amber_outlined
                        : categoryIcon(tips[i].bucket!),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text(l10n, tips[i]))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Where did my money go?": the last 7 days by category.
class CategoryCard extends StatelessWidget {
  const CategoryCard({super.key, required this.totals});

  final List<CategoryTotal> totals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sum = totals.fold<int>(0, (a, t) => a + t.totalFils);
    return Card(
      key: const Key('categoryCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.weekWhereTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              totals.isEmpty
                  ? l10n.weekWhereEmpty
                  : l10n.weekWhereSubtitle(l10n.bhd(formatFils(sum))),
              style: theme.textTheme.bodySmall,
            ),
            for (final t in totals) ...[
              const SizedBox(height: 12),
              Row(
                key: Key('cat_${t.bucket}'),
                children: [
                  Icon(categoryIcon(t.bucket), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(categoryName(l10n, t.bucket)),
                            ),
                            Text(
                              l10n.bhd(formatFils(t.totalFils)),
                              style: theme.textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: sum == 0 ? 0 : t.totalFils / sum,
                            minHeight: 6,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 44,
                    child: Text(
                      l10n.categoryShare(
                          sum == 0 ? 0 : (100 * t.totalFils / sum).round()),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
