import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_picker.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:flutter/material.dart';

class AmountInput {
  const AmountInput(this.fils, {this.merchant, this.category});

  final int fils;
  final String? merchant;

  /// Chosen by the person; null leaves it to the shop name.
  final String? category;
}

/// Asks for an amount in BHD (and optionally where it was spent).
/// Returns null when the user cancels.
Future<AmountInput?> showAmountDialog(
  BuildContext context, {
  required String title,
  bool withMerchant = false,
  bool withCategory = false,
  List<String> customCategories = const [],
  int? initialFils,
  String? initialMerchant,
}) =>
    showDialog<AmountInput>(
      context: context,
      builder: (_) => AmountDialog(
        title: title,
        withMerchant: withMerchant,
        withCategory: withCategory,
        customCategories: customCategories,
        initialFils: initialFils,
        initialMerchant: initialMerchant,
      ),
    );

class AmountDialog extends StatefulWidget {
  const AmountDialog({
    super.key,
    required this.title,
    this.withMerchant = false,
    this.withCategory = false,
    this.customCategories = const [],
    this.initialFils,
    this.initialMerchant,
  });

  final String title;
  final bool withMerchant;
  final bool withCategory;
  final List<String> customCategories;
  final int? initialFils;
  final String? initialMerchant;

  @override
  State<AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<AmountDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.initialFils == null
        ? ''
        : formatFils(widget.initialFils!, group: false),
  );
  late final TextEditingController _merchant =
      TextEditingController(text: widget.initialMerchant ?? '');
  bool _invalid = false;
  String? _category;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    super.dispose();
  }

  void _submit() {
    final fils = parseBhdToFils(_amount.text);
    if (fils == null) {
      setState(() => _invalid = true);
      return;
    }
    final merchant = _merchant.text.trim();
    Navigator.of(context).pop(AmountInput(
      fils,
      merchant: merchant.isEmpty ? null : merchant,
      category: _category,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('amountField'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.amountLabel,
              errorText: _invalid ? l10n.invalidAmount : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.withMerchant)
            TextField(
              key: const Key('merchantField'),
              controller: _merchant,
              maxLength: 40,
              decoration: InputDecoration(labelText: l10n.merchantLabel),
            ),
          if (widget.withCategory)
            InkWell(
              key: const Key('categoryField'),
              onTap: () async {
                final picked = await pickCategory(
                  context,
                  current: _category ?? kUnsortedBucket,
                  custom: [
                    ...widget.customCategories,
                    if (_category != null &&
                        !widget.customCategories.contains(_category) &&
                        isCustomCategory(_category!))
                      _category!,
                  ],
                );
                if (picked != null && mounted) {
                  setState(() => _category = picked);
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.categoryLabel,
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                child: Text(_category == null
                    ? l10n.categoryAuto
                    : categoryName(l10n, _category!)),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('saveAmount'),
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
