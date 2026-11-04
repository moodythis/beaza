import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:flutter/material.dart';

class AmountInput {
  const AmountInput(this.fils, {this.merchant});

  final int fils;
  final String? merchant;
}

/// Asks for an amount in BHD (and optionally where it was spent).
/// Returns null when the user cancels.
Future<AmountInput?> showAmountDialog(
  BuildContext context, {
  required String title,
  bool withMerchant = false,
  int? initialFils,
  String? initialMerchant,
}) =>
    showDialog<AmountInput>(
      context: context,
      builder: (_) => AmountDialog(
        title: title,
        withMerchant: withMerchant,
        initialFils: initialFils,
        initialMerchant: initialMerchant,
      ),
    );

class AmountDialog extends StatefulWidget {
  const AmountDialog({
    super.key,
    required this.title,
    this.withMerchant = false,
    this.initialFils,
    this.initialMerchant,
  });

  final String title;
  final bool withMerchant;
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
    Navigator.of(context)
        .pop(AmountInput(fils, merchant: merchant.isEmpty ? null : merchant));
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
