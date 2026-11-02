import 'package:beaza/app.dart';
import 'package:beaza/data/services/key_store.dart';
import 'package:beaza/data/services/storage.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
    )..load();
    runApp(BeazaApp(homeViewModel: homeViewModel));
  } on Object {
    // Never replace unreadable data with an empty database.
    runApp(const StartupErrorApp());
  }
}
