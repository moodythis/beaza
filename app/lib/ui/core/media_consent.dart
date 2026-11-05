import 'package:beaza/data/services/media_ai_api.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:flutter/material.dart';

/// The "use AI for photos and voice" switch: turning it on first asks for
/// the separate consent, which says exactly what is sent.
class MediaAiSwitch extends StatefulWidget {
  const MediaAiSwitch({super.key, required this.consent, this.onChanged});

  final MediaAiConsent consent;
  final ValueChanged<bool>? onChanged;

  @override
  State<MediaAiSwitch> createState() => _MediaAiSwitchState();
}

class _MediaAiSwitchState extends State<MediaAiSwitch> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    widget.consent.isOn().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  Future<void> _set(bool value) async {
    if (value) {
      final l10n = AppLocalizations.of(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l10n.mediaAiTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.mediaAiConsent),
                TextButton(
                  key: const Key('mediaAiPrivacy'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => openLegal(d, privacyNotice,
                      section: kPrivacyMediaSection),
                  child: Text(l10n.privacyDetails),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('mediaAiAgree'),
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(l10n.mediaAiAgree),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await widget.consent.turnOn();
    } else {
      await widget.consent.turnOff();
    }
    if (!mounted) return;
    setState(() => _on = value);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      key: const Key('mediaAiSwitch'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.auto_awesome_outlined),
      title: Text(l10n.mediaAiSwitch),
      subtitle: Text(l10n.mediaAiSwitchHint),
      value: _on,
      onChanged: _set,
    );
  }
}
