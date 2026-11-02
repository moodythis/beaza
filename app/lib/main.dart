import 'package:beaza/app.dart';
import 'package:beaza/data/services/alert_notifier.dart';
import 'package:beaza/data/services/key_store.dart';
import 'package:beaza/data/services/sms_source.dart';
import 'package:beaza/data/services/storage.dart';
import 'package:beaza/domain/use_cases/guardrail_alerts.dart';
import 'package:beaza/domain/use_cases/message_intake.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/alert_text.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Kept for the life of the app so new bank messages are read on resume.
AppLifecycleListener? appLifecycle;

/// The phone's language if supported, otherwise Arabic (as the app does).
AppLocalizations phoneLocalizations() {
  final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return lookupAppLocalizations(Locale(code == 'en' ? 'en' : 'ar'));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final storage = await openStorage(
      directory: await getApplicationSupportDirectory(),
      keys: SecureKeyStore(),
    );
    final notifier = PlatformAlertNotifier();
    final alerts = GuardrailAlerts(
      ledger: storage.ledger,
      settings: storage.settings,
      logs: storage.alertLogs,
      present: (alert) {
        final text = alertText(phoneLocalizations(), alert);
        return notifier.show(
          id: alertId(alert.summary.day, alert.level),
          title: text.title,
          body: text.body,
        );
      },
    );
    // Every change to the ledger or the limit re-checks the thresholds.
    storage.ledger.addListener(alerts.evaluate);
    storage.settings.addListener(alerts.evaluate);

    // Dependencies are wired by hand: few objects, no service locator needed.
    final homeViewModel = HomeViewModel(
      ledger: storage.ledger,
      settings: storage.settings,
      intake: MessageIntake(
        sms: PlatformSmsSource(),
        ledger: storage.ledger,
        seen: storage.seenMessages,
      ),
    )..load();
    appLifecycle = AppLifecycleListener(onResume: () {
      homeViewModel.checkMessages();
      alerts.evaluate();
    });
    runApp(BeazaApp(homeViewModel: homeViewModel));

    await notifier.requestPermission().catchError((Object _) => false);
    await homeViewModel.checkMessages();
    await alerts.evaluate();
  } on Object {
    // Never replace unreadable data with an empty database.
    runApp(const StartupErrorApp());
  }
}
