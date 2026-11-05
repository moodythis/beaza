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

  bool get _confirmed => confirmsLastGroup(_confirm.text, _lastGroup);

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
                // The last group is highlighted: it is what gets typed below.
                child: SelectableText.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: _text
                            .substring(0, _text.length - _lastGroup.length)
                            .replaceAll('-', ' - ')),
                    TextSpan(
                      text: _lastGroup,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ]),
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
              // An English keyboard on Android, so Arabic letters are not typed.
              keyboardType: TextInputType.visiblePassword,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: l10n.confirmKeyLabel,
                helperText: l10n.confirmKeyHelp(_lastGroup.length),
                helperMaxLines: 2,
                suffixIcon: _confirmed
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
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

/// Whether [typed] is the key's last group: case, spaces and dashes do not
/// matter, Arabic-Indic digits count as digits, and the look-alikes O
/// (zero) and I, L (one) are accepted, as when the key is read back.
bool confirmsLastGroup(String typed, String lastGroup) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in typed.toUpperCase().split('')) {
    final a = arabic.indexOf(ch);
    final p = persian.indexOf(ch);
    if (a >= 0) {
      b.write(a);
    } else if (p >= 0) {
      b.write(p);
    } else if (ch != ' ' && ch != '-') {
      b.write(ch);
    }
  }
  final normal =
      b.toString().replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
  return normal == lastGroup;
}
