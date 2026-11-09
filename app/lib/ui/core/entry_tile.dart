import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/entry_text.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';

/// One transaction in a list: category icon, name, time and bank, amount.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, this.onTap});

  final LedgerEntry entry;

  /// Opens the category list.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = entry.result;
    final subtitle = entrySubtitle(l10n, r);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Tooltip(
        message: entry.role == EntryRole.spending
            ? categoryName(l10n, bucketOf(r))
            : '',
        child: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          child: Icon(
            switch (entry.role) {
              EntryRole.income => Icons.south_west,
              EntryRole.repayment => Icons.reply,
              EntryRole.internalTransfer => Icons.swap_horiz,
              _ => categoryIcon(bucketOf(r)),
            },
            size: 20,
          ),
        ),
      ),
      title: Text(entryTitle(l10n, r)),
      subtitle: entry.role == EntryRole.repayment
          ? Text(subtitle.isEmpty
              ? l10n.repaidNote
              : '$subtitle · ${l10n.repaidNote}')
          : subtitle.isEmpty
              ? null
              : Text(subtitle),
      trailing: Text(
        '${entry.role == EntryRole.income || entry.role == EntryRole.repayment ? '+' : ''}${l10n.bhd(formatFils(r.amountFils ?? 0))}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}
