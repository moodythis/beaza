import 'dart:async';

import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/sync_repository.dart';
import 'package:beaza/data/services/account_store.dart';
import 'package:beaza/data/services/alert_notifier.dart';
import 'package:beaza/data/services/coach_api.dart';
import 'package:beaza/data/services/device_service.dart';
import 'package:beaza/data/services/google_auth.dart';
import 'package:beaza/data/services/key_store.dart';
import 'package:beaza/data/services/receipt_scanner.dart';
import 'package:beaza/data/services/sms_source.dart';
import 'package:beaza/data/services/storage.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza/data/services/voice_input.dart';
import 'package:beaza/domain/use_cases/data_export.dart';
import 'package:beaza/domain/use_cases/guardrail_alerts.dart';
import 'package:beaza/domain/use_cases/message_intake.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/alert_text.dart';
import 'package:beaza/ui/core/language_controller.dart';
import 'package:beaza/ui/features/coach/view_models/coach_view_model.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Kept for the life of the app so new bank messages are read on resume.
AppLifecycleListener? appLifecycle;

/// Texts for notifications: the language chosen with the button, otherwise
/// the phone's language if English, otherwise Arabic.
AppLocalizations notificationLocalizations(String? chosen) => lookupAppLocalizations(
      Locale(effectiveLanguage(
          chosen, WidgetsBinding.instance.platformDispatcher.locale)),
    );

Future<Storage> openAppStorage() async => openStorage(
      directory: await getApplicationSupportDirectory(),
      keys: SecureKeyStore(),
    );

GuardrailAlerts buildAlerts(
  Storage storage,
  AlertNotifier notifier,
  String? Function() chosenLanguage,
) =>
    GuardrailAlerts(
      ledger: storage.ledger,
      settings: storage.settings,
      logs: storage.alertLogs,
      present: (alert) {
        final text =
            alertText(notificationLocalizations(chosenLanguage()), alert);
        return notifier.show(
          id: alertId(alert.summary.day, alert.level),
          title: text.title,
          body: text.body,
        );
      },
    );

MessageIntake buildIntake(Storage storage) => MessageIntake(
      sms: PlatformSmsSource(),
      ledger: storage.ledger,
      seen: storage.seenMessages,
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final storage = await openAppStorage();
    final language = LanguageController(storage.preferences);
    await language.load();
    final notifier = PlatformAlertNotifier();
    final alerts = buildAlerts(storage, notifier, () => language.code);
    // Every change to the ledger or the limit re-checks the thresholds.
    storage.ledger.addListener(alerts.evaluate);
    storage.settings.addListener(alerts.evaluate);

    // Dependencies are wired by hand: few objects, no service locator needed.
    final device = PlatformDeviceService();
    final homeViewModel = HomeViewModel(
      ledger: storage.ledger,
      settings: storage.settings,
      intake: buildIntake(storage),
      device: device,
      voice: PlatformVoiceInput(),
      receipts: PlatformReceiptScanner(),
      savings: SavingsViewModel(
        repo: SavingsRepository(storage.preferences),
        ledger: storage.ledger,
      )..load(),
      coach: CoachViewModel(
        api: HttpCoachApi(),
        preferences: storage.preferences,
        ledger: storage.ledger,
        settings: storage.settings,
      )..load(),
      export: DataExport(
        ledger: storage.ledger,
        settings: storage.settings,
        device: device,
      ),
    )..load();
    // The sync account. Nothing is sent anywhere until the user creates an
    // account or logs in.
    final api = SyncApi();
    final account = RemoteAccountRepository(
      api: api,
      store: SecureAccountStore(),
      google: PluginGoogleAuth(),
    );
    await account.load().catchError((Object _) {});
    final sync = SyncRepository(
      api: api,
      account: account,
      collections: storage.syncables,
      preferences: storage.preferences,
    );
    await sync.load().catchError((Object _) {});
    account.addListener(sync.accountChanged);
    storage.ledger.addListener(sync.localChanged);
    storage.settings.addListener(sync.localChanged);

    appLifecycle = AppLifecycleListener(onResume: () {
      homeViewModel.checkMessages();
      alerts.evaluate();
      if (account.signedIn) sync.syncNow();
    });
    runApp(BeazaApp(
      homeViewModel: homeViewModel,
      language: language,
      account: account,
      sync: sync,
    ));
    if (account.signedIn) unawaited(sync.syncNow());

    await notifier.requestPermission().catchError((Object _) => false);
    await homeViewModel.checkMessages();
    await alerts.evaluate();
  } on Object {
    // Never replace unreadable data with an empty database.
    runApp(const StartupErrorApp());
  }
}

/// Started by Android (SmsReceiver.kt) when an SMS arrives while the app is
/// closed. Reads new bank messages, stores the transactions, alerts if a
/// threshold was crossed, and tells Android it is done. No screen.
@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const done = MethodChannel('beaza/background');
  Storage? storage;
  try {
    storage = await openAppStorage();
    final intake = buildIntake(storage);
    if (await intake.hasPermission()) {
      await intake.scanUntilFound();
    }
    final chosen = await storage.preferences.read(LanguageController.prefName);
    await buildAlerts(storage, PlatformAlertNotifier(), () => chosen)
        .evaluate();
    await _pushInBackground(storage);
  } on Object {
    // Nothing to show without a screen; the app rescans when opened.
  } finally {
    await storage?.database.close();
    await done.invokeMethod<void>('done').catchError((Object _) {});
  }
}

/// Sends the new transaction to the account's other phones right away, if
/// there is an account. Push only, with a short limit: Android gives a
/// background run only a few seconds, and anything not sent now goes on the
/// next sync from the app.
Future<void> _pushInBackground(Storage storage) async {
  final account = RemoteAccountRepository(
    api: SyncApi(timeout: const Duration(seconds: 4)),
    store: SecureAccountStore(),
  );
  await account.load();
  if (!account.signedIn) return;
  final sync = SyncRepository(
    api: SyncApi(timeout: const Duration(seconds: 4)),
    account: account,
    collections: storage.syncables,
    preferences: storage.preferences,
  );
  await sync
      .syncNow(pushOnly: true)
      .timeout(const Duration(seconds: 5), onTimeout: () => false);
}
