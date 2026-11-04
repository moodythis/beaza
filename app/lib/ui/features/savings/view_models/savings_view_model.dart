import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/rewards_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/rewards.dart' as rw;
import 'package:beaza/domain/use_cases/rewards.dart' show DemoOffer, kDemoOffers, rankOffers;
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/domain/use_cases/subscriptions.dart';
import 'package:beaza_extraction/beaza_extraction.dart' show Day;
import 'package:flutter/foundation.dart';

/// Savings goal, cooling-off holds and repeating charges.
class SavingsViewModel extends ChangeNotifier {
  SavingsViewModel({
    required this.repo,
    required LedgerRepository ledger,
    this.rewards,
    SettingsRepository? settings,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _settings = settings,
        _clock = clock ?? DateTime.now {
    repo.addListener(load);
    _ledger.addListener(load);
    rewards?.addListener(load);
  }

  /// Demo points and offers; null hides them.
  final RewardsRepository? rewards;
  final SettingsRepository? _settings;

  int pointsEarned = 0;
  List<Redemption> redeemed = const [];
  List<DemoOffer> offers = kDemoOffers;
  bool personalOffers = false;

  int get pointsBalance =>
      pointsEarned - redeemed.fold(0, (a, r) => a + r.cost);

  /// Redeems [offer] if there are enough points; returns the code.
  Future<String?> redeem(DemoOffer offer) async {
    final r = rewards;
    if (r == null || pointsBalance < offer.cost) return null;
    final code = offer.codeFor(redeemed.length + 1);
    await r.redeem(offer.id, code, offer.cost);
    return code;
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
    final entries = await _ledger.entries();
    subscriptions = findSubscriptions(entries);
    final r = rewards;
    final s = _settings;
    if (r != null && s != null) {
      final today = Day.of(_clock());
      pointsEarned = rw.pointsEarned(entries, await s.load(), holds, today);
      redeemed = await r.redeemed();
      personalOffers = await r.personal();
      offers = rankOffers(
        spendingByCategory(entries, today.addDays(-6), today),
        personal: personalOffers,
      );
    }
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
    rewards?.removeListener(load);
    super.dispose();
  }
}
