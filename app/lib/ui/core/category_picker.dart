import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/text_dialog.dart';
import 'package:beaza_extraction/beaza_extraction.dart' show kCategories;
import 'package:flutter/material.dart';

/// Asks which category a transaction belongs to. Returns null when the
/// person closes the list without choosing. When [shop] is given, the list
/// says that the choice applies to every purchase from it. [custom] are
/// the person's own categories; the last row makes a new one.
Future<String?> pickCategory(
  BuildContext context, {
  required String current,
  String? shop,
  List<String> custom = const [],
}) async {
  final l10n = AppLocalizations.of(context);
  final picked = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
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
          for (final c in custom)
            ListTile(
              key: Key('pick_$c'),
              leading: Icon(categoryIcon(c)),
              title: Text(categoryName(l10n, c)),
              trailing: c == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(c),
            ),
          ListTile(
            key: const Key('pickNewCategory'),
            leading: const Icon(Icons.add),
            title: Text(l10n.newCategory),
            onTap: () => Navigator.of(context).pop(_newCategory),
          ),
        ],
      ),
    ),
  );
  if (picked != _newCategory || !context.mounted) return picked;
  return askCategoryName(context);
}

const String _newCategory = '__new__';

/// Asks for the name of a new category; null when cancelled or empty.
Future<String?> askCategoryName(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final name = await askText(context,
      title: l10n.newCategory,
      label: l10n.newCategoryName,
      maxLength: kCustomCategoryMaxLength,
      fieldKey: const Key('newCategoryField'),
      saveKey: const Key('saveNewCategory'));
  return name == null ? null : customCategory(name);
}
