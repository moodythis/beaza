import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:flutter/material.dart';

void main() {
  // Dependencies are wired by hand: few objects, no service locator needed.
  final homeViewModel = HomeViewModel(
    ledger: InMemoryLedgerRepository(),
    settings: InMemorySettingsRepository(),
  )..load();
  runApp(BeazaApp(homeViewModel: homeViewModel));
}
