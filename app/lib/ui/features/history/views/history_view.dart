import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/amount_dialog.dart';
import 'package:beaza/ui/core/category_picker.dart';
import 'package:beaza/ui/core/entry_text.dart';
import 'package:beaza/ui/core/entry_tile.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/core/privacy_button.dart';
import 'package:beaza/ui/features/history/view_models/history_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// All transactions, grouped by day. Tap a purchase to change its category.
class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.viewModel, this.onReport});

  final HistoryViewModel viewModel;

  /// Opens the weekly report; null hides the button.
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = DateFormat.yMMMEd(locale);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          if (onReport != null)
            IconButton(
              key: const Key('historyReport'),
              tooltip: l10n.weeklyReport,
              icon: const Icon(Icons.summarize_outlined),
              onPressed: onReport,
            ),
          const PrivacyButton(),
        ],
      ),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          if (!viewModel.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final filter = Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilterChip(
              key: const Key('unsortedOnly'),
              avatar: const Icon(Icons.help_outline, size: 18),
              label: Text(l10n.historyUnsortedOnly(viewModel.unsortedCount)),
              selected: viewModel.unsortedOnly,
              onSelected: viewModel.showUnsortedOnly,
            ),
          );
          if (viewModel.days.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (viewModel.unsortedOnly || viewModel.unsortedCount > 0)
                  filter,
                const SizedBox(height: 32),
                Center(
                  child: Text(viewModel.unsortedOnly
                      ? l10n.historyAllSorted
                      : l10n.historyEmpty),
                ),
              ],
            );
          }
          // One flat list of rows, built only as they scroll into view: a
          // year of messages is about 2,000 rows.
          final rows = <Object>[
            if (viewModel.unsortedOnly || viewModel.unsortedCount > 0) #filter,
            if (viewModel.unsortedOnly && viewModel.autoSort != null) #autoSort,
            for (final d in viewModel.days) ...[d, ...d.entries],
          ];
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              if (row == #filter) return filter;
              if (row == #autoSort) return _autoSortCard(context, l10n);
              if (row is HistoryDay) {
                final d = row;
                return Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Row(
                    key: Key('day_${d.day}'),
                    children: [
                      Expanded(
                        child: Text(
                          format.format(DateTime.utc(
                              d.day.year, d.day.month, d.day.day)),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (d.spentFils > 0)
                        Text(
                          l10n.historyDaySpent(
                              l10n.bhd(formatFils(d.spentFils))),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                );
              }
              final e = row as LedgerEntry;
              return _swipeToDelete(
                context,
                e,
                EntryTile(
                  entry: e,
                  // Sorting is the common job, so the unsorted list goes
                  // straight to the categories.
                  onTap: viewModel.unsortedOnly
                      ? () => _choose(context, e)
                      : () => _actions(context, e),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _autoSortCard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    if (viewModel.autoSortOn) {
      return Card(
        key: const Key('autoSortOnCard'),
        child: ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: Text(l10n.autoSortIsOn, style: theme.textTheme.bodyMedium),
          trailing: TextButton(
            key: const Key('autoSortOff'),
            onPressed: viewModel.turnOffAutoSort,
            child: Text(l10n.autoSortStop),
          ),
        ),
      );
    }
    return Card(
      key: const Key('autoSortCard'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.autoSortExplain, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const Key('autoSortOn'),
              icon: const Icon(Icons.auto_awesome),
              label: Text(l10n.autoSortButton),
              onPressed: () => _turnOnAutoSort(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _turnOnAutoSort(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.autoSortConsentTitle),
        content: Text(l10n.autoSortConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('autoSortAgree'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.autoSortAgree),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final n = await viewModel.turnOnAutoSort();
    messenger.showSnackBar(SnackBar(content: Text(l10n.autoSortDone(n))));
  }

  Future<void> _actions(BuildContext context, LedgerEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(entryTitle(l10n, entry.result),
                  style: Theme.of(sheet).textTheme.titleMedium),
              trailing: Text(l10n.bhd(formatFils(entry.result.amountFils ?? 0))),
            ),
            if (entry.role == EntryRole.income ||
                entry.role == EntryRole.repayment)
              SwitchListTile(
                key: const Key('entryRepaid'),
                secondary: const Icon(Icons.reply),
                title: Text(l10n.repaidSwitch),
                subtitle: Text(l10n.repaidHint),
                value: entry.role == EntryRole.repayment,
                onChanged: (v) =>
                    Navigator.of(sheet).pop(v ? 'repaid' : 'notRepaid'),
              ),
            if (entry.role == EntryRole.spending)
              ListTile(
                key: const Key('entryCategory'),
                leading: const Icon(Icons.category_outlined),
                title: Text(l10n.entryChangeCategory),
                onTap: () => Navigator.of(sheet).pop('category'),
              ),
            ListTile(
              key: const Key('entryEdit'),
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.entryEdit),
              onTap: () => Navigator.of(sheet).pop('edit'),
            ),
            ListTile(
              key: const Key('entryDelete'),
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(sheet).colorScheme.error),
              title: Text(l10n.entryDelete,
                  style: TextStyle(color: Theme.of(sheet).colorScheme.error)),
              onTap: () => Navigator.of(sheet).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'category':
        await _choose(context, entry);
      case 'edit':
        await _edit(context, entry);
      case 'delete':
        await _delete(context, entry);
      case 'repaid':
        await viewModel.setRepayment(entry, true);
      case 'notRepaid':
        await viewModel.setRepayment(entry, false);
    }
  }

  Future<void> _edit(BuildContext context, LedgerEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final r = entry.result;
    final shop = (r.merchantNorm ?? r.merchantRaw)?.trim();
    final input = await showAmountDialog(
      context,
      title: l10n.entryEditTitle,
      withMerchant: true,
      initialFils: r.amountFils,
      initialMerchant: shop,
    );
    if (input == null) return;
    await viewModel.edit(entry,
        amountFils: input.fils, merchant: input.merchant);
  }

  /// A drag from the left edge to the right deletes, in Arabic and in
  /// English alike: Dismissible's start-to-end follows the text direction,
  /// so in right-to-left it is end-to-start. Asks first; a "no" springs back.
  Widget _swipeToDelete(BuildContext context, LedgerEntry e, Widget child) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Dismissible(
      key: ValueKey('swipe_${e.index}_${e.result.timestamp}_${e.result.amountFils}'),
      direction:
          rtl ? DismissDirection.endToStart : DismissDirection.startToEnd,
      // A clear drag, but not across the whole screen.
      dismissThresholds: {
        rtl ? DismissDirection.endToStart : DismissDirection.startToEnd: 0.3,
      },
      background: Container(
        color: theme.colorScheme.error,
        // Physically on the left, where the drag starts.
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            Icon(Icons.delete_outline, color: theme.colorScheme.onError),
            const SizedBox(width: 8),
            Text(l10n.entryDelete,
                style: TextStyle(color: theme.colorScheme.onError)),
          ],
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(context, e),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        await viewModel.dismiss(e);
        messenger.showSnackBar(SnackBar(content: Text(l10n.entryDeleted)));
      },
      child: child,
    );
  }

  Future<bool> _confirmDelete(BuildContext context, LedgerEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.entryDeleteTitle),
        content: Text(
            '${entryTitle(l10n, entry.result)} · ${l10n.bhd(formatFils(entry.result.amountFils ?? 0))}\n\n${l10n.entryDeleteBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirmDelete'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.entryDelete),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _delete(BuildContext context, LedgerEntry entry) async {
    if (await _confirmDelete(context, entry)) await viewModel.remove(entry);
  }

  Future<void> _choose(BuildContext context, LedgerEntry entry) async {
    final current = bucketOf(entry.result);
    final custom = await viewModel.customCategories();
    if (!context.mounted) return;
    final picked = await pickCategory(
      context,
      current: current,
      shop: shopName(entry.result),
      custom: custom,
    );
    if (picked == null || picked == current) return;
    await viewModel.setCategory(entry, picked);
  }
}
