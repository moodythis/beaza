import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_picker.dart';
import 'package:beaza/ui/core/entry_text.dart';
import 'package:beaza/ui/core/entry_tile.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/history/view_models/history_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// All transactions, grouped by day. Tap a purchase to change its category.
class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.viewModel});

  final HistoryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = DateFormat.yMMMEd(locale);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          if (!viewModel.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (viewModel.days.isEmpty) {
            return Center(child: Text(l10n.historyEmpty));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              for (final d in viewModel.days) ...[
                Padding(
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
                ),
                for (final e in d.entries)
                  EntryTile(
                    entry: e,
                    onTap: e.role == EntryRole.spending
                        ? () => _choose(context, e)
                        : null,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _choose(BuildContext context, LedgerEntry entry) async {
    final current = bucketOf(entry.result);
    final picked = await pickCategory(
      context,
      current: current,
      shop: shopName(entry.result),
    );
    if (picked == null || picked == current) return;
    await viewModel.setCategory(entry, picked);
  }
}
