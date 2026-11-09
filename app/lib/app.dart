import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/sync_repository.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/language_controller.dart';
import 'package:beaza/ui/core/theme.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/home/views/home_shell.dart';
import 'package:flutter/material.dart';

class BeazaApp extends StatelessWidget {
  const BeazaApp({
    super.key,
    required this.homeViewModel,
    this.language,
    this.locale,
    this.account,
    this.sync,
  });

  final HomeViewModel homeViewModel;

  /// The sync account; null hides the account button (tests).
  final AccountRepository? account;

  /// Sync between phones; null in tests that do not need it.
  final SyncRepository? sync;

  /// The language button's state; null hides the button (tests).
  final LanguageController? language;

  /// Fixed locale for tests. Otherwise the button's choice, then the phone.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    final controller = language;
    if (controller == null) return _app(locale);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _app(locale ?? controller.locale),
    );
  }

  Widget _app(Locale? chosen) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        locale: chosen,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: HomeShell(
          viewModel: homeViewModel,
          language: language,
          account: account,
          sync: sync,
        ),
      );
}

/// Shown when the database cannot be opened. Nothing is deleted or reset.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => Text(AppLocalizations.of(context).loadError),
          ),
        ),
      ),
    );
  }
}
