import 'package:beaza/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Asks for one line of text. Null when cancelled. The text field's
/// controller lives in the dialog's own state, so it is disposed only after
/// the closing animation (disposing it right after showDialog returns
/// breaks that animation).
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  int maxLength = 40,
  Key? fieldKey,
  Key? saveKey,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: title,
        label: label,
        maxLength: maxLength,
        fieldKey: fieldKey,
        saveKey: saveKey,
      ),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.maxLength,
    this.fieldKey,
    this.saveKey,
  });

  final String title;
  final String label;
  final int maxLength;
  final Key? fieldKey;
  final Key? saveKey;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: widget.fieldKey,
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: widget.saveKey,
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
