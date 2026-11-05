import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
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
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(l10n.newCategory),
      content: TextField(
        key: const Key('newCategoryField'),
        controller: controller,
        autofocus: true,
        maxLength: kCustomCategoryMaxLength,
        decoration: InputDecoration(labelText: l10n.newCategoryName),
        onSubmitted: (v) => Navigator.of(d).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(d).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('saveNewCategory'),
          onPressed: () => Navigator.of(d).pop(controller.text),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  controller.dispose();
  return name == null ? null : customCategory(name);
}
