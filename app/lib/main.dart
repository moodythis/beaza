import 'package:beaza/app.dart';
import 'package:beaza/data/services/key_store.dart';
import 'package:beaza/data/services/sms_source.dart';
import 'package:beaza/data/services/storage.dart';
import 'package:beaza/domain/use_cases/message_intake.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Kept for the life of the app so new bank messages are read on resume.
AppLifecycleListener? appLifecycle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final storage = await openStorage(
      directory: await getApplicationSupportDirectory(),
      keys: SecureKeyStore(),
    );
    // Dependencies are wired by hand: few objects, no service locator needed.
    final homeViewModel = HomeViewModel(
      ledger: storage.ledger,
      settings: storage.settings,
      intake: MessageIntake(
        sms: PlatformSmsSource(),
        ledger: storage.ledger,
        seen: storage.seenMessages,
      ),
    )
      ..load()
      ..checkMessages();
    appLifecycle = AppLifecycleListener(onResume: homeViewModel.checkMessages);
    runApp(BeazaApp(homeViewModel: homeViewModel));
  } on Object {
    // Never replace unreadable data with an empty database.
    runApp(const StartupErrorApp());
  }
}
