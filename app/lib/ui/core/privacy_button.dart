import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:flutter/material.dart';

/// Where privacy mode is remembered.
const String kHideAmountsKey = 'privacy.hideAmounts';

/// Reads privacy mode back and keeps it saved from now on.
Future<void> loadPrivacyMode(PreferencesStore prefs) async {
  amountsHidden.value = await prefs.read(kHideAmountsKey) == '1';
  amountsHidden.addListener(
      () => prefs.write(kHideAmountsKey, amountsHidden.value ? '1' : null));
}

/// Redraws every screen, including ones under the current one, so all
/// amounts follow the eye at once.
void _redrawAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

/// The eye in the top bar: hides or shows every amount in the app.
class PrivacyButton extends StatelessWidget {
  const PrivacyButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: amountsHidden,
      builder: (context, hidden, _) => IconButton(
        key: const Key('privacyButton'),
        tooltip: hidden ? l10n.privacyShow : l10n.privacyHide,
        icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        onPressed: () {
          amountsHidden.value = !hidden;
          _redrawAll();
        },
      ),
    );
  }
}
