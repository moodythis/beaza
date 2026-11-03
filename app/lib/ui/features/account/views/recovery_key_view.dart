import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the recovery key once, right after sign-up. The screen cannot be
/// left until the person types the last group, which shows they saved it.
class RecoveryKeyView extends StatefulWidget {
  const RecoveryKeyView({super.key, required this.recoveryKey});

  final RecoveryKey recoveryKey;

  @override
  State<RecoveryKeyView> createState() => _RecoveryKeyViewState();
}

class _RecoveryKeyViewState extends State<RecoveryKeyView> {
  final _confirm = TextEditingController();
  late final String _text = widget.recoveryKey.format();
  late final String _lastGroup = _text.split('-').last;

  bool get _confirmed {
    final typed = _confirm.text
        .trim()
        .toUpperCase()
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    return typed == _lastGroup;
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: _confirmed,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.recoveryKeyTitle),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.recoveryKeyBody, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _text.replaceAll('-', ' - '),
                  key: const Key('recoveryKeyText'),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            Align(
              child: TextButton.icon(
                key: const Key('copyKey'),
                icon: const Icon(Icons.copy),
                label: Text(l10n.copyKey),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l10n.keyCopied)));
                },
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('confirmKeyField'),
              controller: _confirm,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              maxLength: 4,
              decoration: InputDecoration(labelText: l10n.confirmKeyLabel),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('recoveryDone'),
              onPressed: _confirmed ? () => Navigator.of(context).pop() : null,
              child: Text(l10n.done),
            ),
          ],
        ),
      ),
    );
  }
}
