import 'package:beaza/data/services/receipt_scanner.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_picker.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/entry_text.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/receipt/view_models/receipt_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';

Future<void> showReceiptSheet(BuildContext context, ReceiptViewModel viewModel) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReceiptSheet(viewModel: viewModel),
    );

/// Choose camera or picture, wait while it is read, then check and edit
/// the amount, shop and category before adding.
class ReceiptSheet extends StatefulWidget {
  const ReceiptSheet({super.key, required this.viewModel});

  final ReceiptViewModel viewModel;

  @override
  State<ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<ReceiptSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _shop = TextEditingController();
  String? _category;
  ExtractionResult? _filledFrom;
  bool _invalid = false;

  ReceiptViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.addListener(_changed);
  }

  @override
  void dispose() {
    vm.removeListener(_changed);
    vm.dispose(); // the sheet owns its view model
    _amount.dispose();
    _shop.dispose();
    super.dispose();
  }

  void _changed() {
    final r = vm.result;
    if (vm.step == ReceiptStep.review && r != null && !identical(r, _filledFrom)) {
      _filledFrom = r;
      _amount.text = r.amountFils == null ? '' : formatFils(r.amountFils!, group: false);
      _shop.text = r.merchantNorm ?? r.merchantRaw ?? '';
      _category = r.category;
      _invalid = false;
    }
    if (vm.step == ReceiptStep.saved && mounted) {
      Navigator.of(context).pop();
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final fils = parseBhdToFils(_amount.text);
    if (fils == null) {
      setState(() => _invalid = true);
      return;
    }
    final shop = _shop.text.trim();
    await vm.save(
      amountFils: fils,
      merchant: shop.isEmpty ? null : shop,
      category: _category,
    );
  }

  Future<void> _chooseCategory() async {
    final picked = await pickCategory(context, current: _category ?? kUnsortedBucket);
    if (picked != null && mounted) setState(() => _category = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.receiptTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ...switch (vm.step) {
              ReceiptStep.choose => _choose(l10n, theme),
              ReceiptStep.scanning || ReceiptStep.saving || ReceiptStep.saved => [
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  Text(l10n.receiptReading, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                ],
              ReceiptStep.failed => [
                  Text(
                    vm.error == 'no_camera' ? l10n.receiptNoCamera : l10n.receiptError,
                    key: const Key('receiptFailed'),
                  ),
                  if (vm.detail != null && vm.error != 'no_camera')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(vm.detail!,
                          key: const Key('receiptDetail'),
                          style: theme.textTheme.bodySmall),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: vm.startOver,
                    child: Text(l10n.receiptAgain),
                  ),
                ],
              ReceiptStep.review => _review(l10n, theme),
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _choose(AppLocalizations l10n, ThemeData theme) => [
        FilledButton.tonalIcon(
          key: const Key('receiptCamera'),
          onPressed: () => vm.scan(ReceiptSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(l10n.receiptCamera),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('receiptGallery'),
          onPressed: () => vm.scan(ReceiptSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(l10n.receiptGallery),
        ),
        const SizedBox(height: 8),
        Text(l10n.receiptPrivacy, style: theme.textTheme.bodySmall),
      ];

  List<Widget> _review(AppLocalizations l10n, ThemeData theme) {
    final r = vm.result!;
    final foreign = r.currency != null && r.currency != 'BHD';
    final notes = <String>[
      if (r.kind == MessageKind.declined)
        l10n.receiptDeclined
      else if (r.amountFils == null)
        l10n.receiptNoAmount,
      if (r.flags.contains(ExtractionFlag.totalGuessed)) l10n.receiptTotalGuessed,
      if (r.flags.contains(ExtractionFlag.currencyAssumed)) l10n.receiptCurrencyAssumed,
      if (foreign) l10n.receiptForeign(r.currency!),
      if (r.flags.contains(ExtractionFlag.timestampFromReceipt)) l10n.receiptNoDate,
    ];
    final dup = vm.duplicate;
    final at = r.timestamp;
    return [
      if (dup != null)
        Card(
          key: const Key('receiptDuplicate'),
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              l10n.receiptDuplicate(
                entryTitle(l10n, dup.result),
                l10n.bhd(formatFils(dup.result.amountFils ?? 0)),
                formatBahrainTime(dup.result.timestamp!),
              ),
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ),
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(n, style: theme.textTheme.bodySmall)),
            ],
          ),
        ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('receiptAmount'),
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: l10n.receiptAmount,
          border: const OutlineInputBorder(),
          errorText: _invalid ? l10n.receiptInvalid : null,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('receiptShop'),
        controller: _shop,
        decoration: InputDecoration(
          labelText: l10n.receiptShop,
          border: const OutlineInputBorder(),
        ),
      ),
      ListTile(
        key: const Key('receiptCategory'),
        contentPadding: EdgeInsets.zero,
        leading: Icon(categoryIcon(_category ?? kUnsortedBucket)),
        title: Text(categoryName(l10n, _category ?? kUnsortedBucket)),
        trailing: const Icon(Icons.chevron_right),
        onTap: _chooseCategory,
      ),
      if (at != null)
        Text(
          l10n.receiptWhen(
              '${Day.of(at).day}/${Day.of(at).month} ${formatBahrainTime(at)}'),
          style: theme.textTheme.bodySmall,
        ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('receiptSkip'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.receiptSkip),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const Key('receiptSave'),
              onPressed: foreign ? null : _save,
              child: Text(dup != null ? l10n.receiptAddAnyway : l10n.receiptSave),
            ),
          ),
        ],
      ),
    ];
  }
}
