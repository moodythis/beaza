import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:flutter/material.dart';

/// What the person returns: a plan to work the limit out from, or "by hand".
class BudgetChoice {
  const BudgetChoice.plan(this.plan);
  const BudgetChoice.byHand() : plan = null;

  final BudgetPlan? plan;
}

Future<BudgetChoice?> showBudgetDialog(BuildContext context, {BudgetPlan? current}) =>
    showDialog<BudgetChoice>(
      context: context,
      builder: (_) => _BudgetDialog(current: current),
    );

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({this.current});

  final BudgetPlan? current;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final TextEditingController _income = TextEditingController(
      text: widget.current == null
          ? ''
          : formatFils(widget.current!.incomeFils, group: false));
  late final TextEditingController _fixed = TextEditingController(
      text: widget.current == null || widget.current!.fixedFils == 0
          ? ''
          : formatFils(widget.current!.fixedFils, group: false));
  bool _invalid = false;

  @override
  void dispose() {
    _income.dispose();
    _fixed.dispose();
    super.dispose();
  }

  void _submit() {
    final income = parseBhdToFils(_income.text);
    final fixed = _fixed.text.trim().isEmpty ? 0 : parseBhdToFils(_fixed.text);
    if (income == null || income <= 0 || fixed == null || fixed >= income) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context)
        .pop(BudgetChoice.plan(BudgetPlan(incomeFils: income, fixedFils: fixed)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.budgetTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.budgetExplain),
            const SizedBox(height: 12),
            TextField(
              key: const Key('budgetIncome'),
              controller: _income,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.budgetIncome,
                errorText: _invalid ? l10n.budgetInvalid : null,
              ),
            ),
            TextField(
              key: const Key('budgetFixed'),
              controller: _fixed,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.budgetFixed),
            ),
            const SizedBox(height: 8),
            Text(l10n.budgetFixedHint,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            key: const Key('budgetByHand'),
            onPressed: () => Navigator.of(context).pop(const BudgetChoice.byHand()),
            child: Text(l10n.budgetByHand),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('budgetSave'),
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
