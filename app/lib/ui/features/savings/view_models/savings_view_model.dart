import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/domain/use_cases/subscriptions.dart';
import 'package:flutter/foundation.dart';

/// Savings goal, cooling-off holds and repeating charges.
class SavingsViewModel extends ChangeNotifier {
  SavingsViewModel({
    required this.repo,
    required LedgerRepository ledger,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _clock = clock ?? DateTime.now {
    repo.addListener(load);
    _ledger.addListener(load);
  }

  final SavingsRepository repo;
  final LedgerRepository _ledger;
  final DateTime Function() _clock;

  DateTime now() => _clock();

  List<Hold> holds = const [];
  Goal? goal;
  List<Subscription> subscriptions = const [];
  bool loaded = false;
  bool _disposed = false;

  Future<void> load() async {
    holds = await repo.holds();
    goal = await repo.goal();
    subscriptions = findSubscriptions(await _ledger.entries());
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  List<Hold> get waiting => [for (final h in holds) if (h.decision == null) h];
  List<Hold> get decided => [for (final h in holds) if (h.decision != null) h];

  int get goalSaved => goal == null ? 0 : goalSavedFils(goal!, holds);
  int get skippedTotal => skippedFils(holds);
  int get subscriptionsMonthly =>
      subscriptions.fold(0, (a, s) => a + s.monthlyFils);

  @override
  void dispose() {
    _disposed = true;
    repo.removeListener(load);
    _ledger.removeListener(load);
    super.dispose();
  }
}
