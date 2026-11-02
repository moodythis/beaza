import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/theme.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/home/views/home_view.dart';
import 'package:flutter/material.dart';

class BeazaApp extends StatelessWidget {
  const BeazaApp({super.key, required this.homeViewModel, this.locale});

  final HomeViewModel homeViewModel;

  /// Null follows the phone's language (Arabic or English).
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomeView(viewModel: homeViewModel),
    );
  }
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
