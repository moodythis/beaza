import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza_extraction/beaza_extraction.dart' show kCategories;
import 'package:flutter/material.dart';

/// Asks which category a transaction belongs to. Returns null when the
/// person closes the list without choosing. When [shop] is given, the list
/// says that the choice applies to every purchase from it.
Future<String?> pickCategory(
  BuildContext context, {
  required String current,
  String? shop,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.chooseCategory,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (shop != null)
                  Text(
                    l10n.categoryAppliesTo(shop),
                    key: const Key('appliesTo'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          for (final c in kCategories)
            ListTile(
              key: Key('pick_$c'),
              leading: Icon(categoryIcon(c)),
              title: Text(categoryName(l10n, c)),
              trailing: c == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(c),
            ),
        ],
      ),
    ),
  );
}
